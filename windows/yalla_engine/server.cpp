#include <winsock2.h>
#include <ws2tcpip.h>
#include <iostream>
#include <string>
#include <sstream>
#include <vector>
#include "yalla_engine.h"

#pragma comment(lib, "ws2_32.lib")

#define PORT 8080
#define BUFFER_SIZE 8192

// Simple URL decoder
std::string url_decode(const std::string& src) {
    std::string dst = "";
    char ch;
    int i, ii;
    for (i = 0; i < src.length(); i++) {
        if (src[i] == '%') {
            if (sscanf_s(src.substr(i + 1, 2).c_str(), "%x", &ii) == 1) {
                ch = (char)ii;
                dst += ch;
                i += 2;
            }
        } else if (src[i] == '+') {
            dst += ' ';
        } else {
            dst += src[i];
        }
    }
    return dst;
}

// Extract query parameter
std::string get_query_param(const std::string& url_query, const std::string& param_name) {
    size_t pos = url_query.find(param_name + "=");
    if (pos == std::string::npos) return "";
    size_t val_start = pos + param_name.length() + 1;
    size_t val_end = url_query.find("&", val_start);
    if (val_end == std::string::npos) {
        return url_query.substr(val_start);
    }
    return url_query.substr(val_start, val_end - val_start);
}

int main() {
    // Initialize Winsock
    WSADATA wsaData;
    int iResult = WSAStartup(MAKEWORD(2, 2), &wsaData);
    if (iResult != 0) {
        std::cerr << "WSAStartup failed with error: " << iResult << "\n";
        return 1;
    }

    // Create a SOCKET for listening
    SOCKET listenSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listenSocket == INVALID_SOCKET) {
        std::cerr << "socket failed with error: " << WSAGetLastError() << "\n";
        WSACleanup();
        return 1;
    }

    // Bind socket to port
    sockaddr_in service;
    service.sin_family = AF_INET;
    service.sin_addr.s_addr = INADDR_ANY;
    service.sin_port = htons(PORT);

    iResult = bind(listenSocket, (SOCKADDR*)&service, sizeof(service));
    if (iResult == SOCKET_ERROR) {
        std::cerr << "bind failed with error: " << WSAGetLastError() << "\n";
        closesocket(listenSocket);
        WSACleanup();
        return 1;
    }

    // Listen on socket
    iResult = listen(listenSocket, SOMAXCONN);
    if (iResult == SOCKET_ERROR) {
        std::cerr << "listen failed with error: " << WSAGetLastError() << "\n";
        closesocket(listenSocket);
        WSACleanup();
        return 1;
    }

    std::cout << "\n============================================\n";
    std::cout << "  YallaNews C++ Native Socket Engine Server  \n";
    std::cout << "  Listening on: http://localhost:" << PORT << "\n";
    std::cout << "============================================\n\n";

    // Initialize C++ engine internally with empty db initially
    init_engine("");

    while (true) {
        SOCKET clientSocket = accept(listenSocket, NULL, NULL);
        if (clientSocket == INVALID_SOCKET) {
            std::cerr << "accept failed with error: " << WSAGetLastError() << "\n";
            continue;
        }

        // Receive request
        char* recvbuf = new char[BUFFER_SIZE];
        int bytesReceived = recv(clientSocket, recvbuf, BUFFER_SIZE - 1, 0);
        if (bytesReceived > 0) {
            recvbuf[bytesReceived] = '\0';
            std::string request(recvbuf);
            
            // Extract HTTP method and path
            std::stringstream ss(request);
            std::string method, full_path, protocol;
            ss >> method >> full_path >> protocol;

            // Simple routing
            std::string response_payload = "";
            std::string status_code = "200 OK";

            if (method == "OPTIONS") {
                // Return standard preflight response for browser CORS requests
                std::stringstream resp;
                resp << "HTTP/1.1 200 OK\r\n"
                     << "Access-Control-Allow-Origin: *\r\n"
                     << "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
                     << "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
                     << "Content-Length: 0\r\n"
                     << "Connection: close\r\n\r\n";
                std::string resp_str = resp.str();
                send(clientSocket, resp_str.c_str(), (int)resp_str.length(), 0);
            } 
            else if (full_path.find("/init") == 0 && method == "POST") {
                // Initialize news database from payload
                size_t body_pos = request.find("\r\n\r\n");
                std::string payload = "";
                if (body_pos != std::string::npos) {
                    payload = request.substr(body_pos + 4);
                }
                init_engine(payload.c_str());
                response_payload = "{\"success\":true,\"message\":\"C++ Engine initialized with custom DB\"}";
            } 
            else if (full_path.find("/process") == 0) {
                // Process news URL
                std::string raw_url = get_query_param(full_path, "url");
                std::string decoded_url = url_decode(raw_url);
                
                if (!decoded_url.empty()) {
                    const char* result_json = process_url(decoded_url.c_str());
                    if (result_json != nullptr) {
                        response_payload = std::string(result_json);
                        free_string(result_json);
                    } else {
                        status_code = "500 Internal Server Error";
                        response_payload = "{\"success\":false,\"error\":\"C++ process failed\"}";
                    }
                } else {
                    status_code = "400 Bad Request";
                    response_payload = "{\"success\":false,\"error\":\"Missing URL parameter\"}";
                }
            } 
            else if (full_path == "/logs") {
                // Fetch logs
                const char* logs_str = get_engine_logs();
                if (logs_str != nullptr) {
                    response_payload = "{\"success\":true,\"logs\":\"" + std::string(logs_str) + "\"}"; // Simplified representation
                    free_string(logs_str);
                } else {
                    response_payload = "{\"success\":true,\"logs\":\"\"}";
                }
            }
            else if (full_path == "/cluster" && method == "POST") {
                // Cluster articles
                size_t body_pos = request.find("\r\n\r\n");
                std::string payload = "";
                if (body_pos != std::string::npos) {
                    payload = request.substr(body_pos + 4);
                }
                const char* result_json = cluster_articles(payload.c_str());
                if (result_json != nullptr) {
                    response_payload = std::string(result_json);
                    free_cluster_string(result_json);
                } else {
                    status_code = "500 Internal Server Error";
                    response_payload = "{\"success\":false,\"error\":\"Clustering failed\"}";
                }
            }
            else if (full_path.find("/cluster_ex") == 0) {
                // Cluster articles with custom parameters
                size_t body_pos = request.find("\r\n\r\n");
                std::string payload = "";
                if (body_pos != std::string::npos) {
                    payload = request.substr(body_pos + 4);
                }
                int32_t algorithm = 1;
                int32_t n_clusters = 0;
                double eps = 0.5;
                int32_t min_samples = 2;
                if (full_path.find("algorithm=") != std::string::npos) {
                    algorithm = std::stoi(get_query_param(full_path, "algorithm"));
                }
                if (full_path.find("n_clusters=") != std::string::npos) {
                    n_clusters = std::stoi(get_query_param(full_path, "n_clusters"));
                }
                if (full_path.find("eps=") != std::string::npos) {
                    eps = std::stod(get_query_param(full_path, "eps"));
                }
                if (full_path.find("min_samples=") != std::string::npos) {
                    min_samples = std::stoi(get_query_param(full_path, "min_samples"));
                }
                const char* result_json = cluster_articles_ex(payload.c_str(), algorithm, n_clusters, eps, min_samples);
                if (result_json != nullptr) {
                    response_payload = std::string(result_json);
                    free_cluster_string(result_json);
                } else {
                    status_code = "500 Internal Server Error";
                    response_payload = "{\"success\":false,\"error\":\"Clustering failed\"}";
                }
            } else {
                // Not Found fallback
                status_code = "404 Not Found";
                response_payload = "{\"success\":false,\"error\":\"Endpoint not found\"}";
            }

            if (method != "OPTIONS") {
                // Dispatch response
                std::stringstream resp;
                resp << "HTTP/1.1 " << status_code << "\r\n"
                     << "Content-Type: application/json; charset=utf-8\r\n"
                     << "Access-Control-Allow-Origin: *\r\n"
                     << "Content-Length: " << response_payload.length() << "\r\n"
                     << "Connection: close\r\n\r\n"
                     << response_payload;
                
                std::string resp_str = resp.str();
                send(clientSocket, resp_str.c_str(), (int)resp_str.length(), 0);
            }
        }

        delete[] recvbuf;
        closesocket(clientSocket);
    }

    closesocket(listenSocket);
    WSACleanup();
    return 0;
}
