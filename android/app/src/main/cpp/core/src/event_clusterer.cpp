#include "yalla_core.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cmath>
#include <random>
#include <unordered_set>
#include <limits>
#include <numeric>
#include <set>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

struct ArticleFeature {
    std::string url;
    std::string title;
    std::string content;
    std::string category;
    std::vector<std::string> keywords;
    std::vector<float> embedding;
};

struct ClusterResult {
    int32_t cluster_id = -1;
    int32_t article_count = 0;
    double distance_to_centroid = 0.0;
};

struct ClusteringOutput {
    std::vector<int32_t> assignments;
    std::vector<ClusterResult> clusters;
    int32_t total_articles = 0;
    int32_t total_clusters = 0;
    std::string algorithm_used;
};

class ClusteringEngine {
public:
    ClusteringEngine() : max_iterations_(100), random_seed_(42), use_pca_(true) {}

    void set_max_iterations(int32_t iters) { max_iterations_ = iters; }
    void enable_pca_reduction(bool enable) { use_pca_ = enable; }

    static double compute_distance(const std::vector<double>& a, const std::vector<double>& b) {
        double sum = 0.0;
        const size_t n = std::min(a.size(), b.size());
        for (size_t i = 0; i < n; ++i) {
            const double diff = a[i] - b[i];
            sum += diff * diff;
        }
        return std::sqrt(sum);
    }

    std::vector<std::vector<double>> compute_feature_matrix(const std::vector<ArticleFeature>& articles) {
        std::vector<std::vector<double>> features;
        features.reserve(articles.size());

        std::unordered_map<std::string, size_t> keyword_index;
        size_t idx = 0;
        for (const auto& article : articles) {
            for (const auto& kw : article.keywords) {
                if (!keyword_index.count(kw)) {
                    keyword_index[kw] = idx++;
                }
            }
        }

        const size_t max_keywords = std::min(idx, static_cast<size_t>(200));

        std::vector<double> idf(keyword_index.size(), 1.0);
        for (const auto& article : articles) {
            std::unordered_map<std::string, int> term_freq;
            for (const auto& kw : article.keywords) {
                ++term_freq[kw];
            }
            for (const auto& [kw, tf] : term_freq) {
                idf[keyword_index[kw]] += tf;
            }
        }

        const double n_docs = static_cast<double>(articles.size());
        for (auto& val : idf) {
            val = std::log(n_docs / (1.0 + val));
        }

        for (const auto& article : articles) {
            std::vector<double> feature;
            feature.reserve(max_keywords + 10);

            std::unordered_map<std::string, int> term_freq;
            for (const auto& kw : article.keywords) {
                ++term_freq[kw];
            }

            for (const auto& [kw, kidx] : keyword_index) {
                if (kidx >= max_keywords) break;
                const double tf = term_freq.count(kw) ? static_cast<double>(term_freq[kw]) : 0.0;
                feature.push_back(tf * idf[kidx]);
            }

            for (size_t i = 0; i < std::min(article.embedding.size(), size_t(10)); ++i) {
                feature.push_back(static_cast<double>(article.embedding[i]));
            }

            while (feature.size() < max_keywords + 10) {
                feature.push_back(0.0);
            }

            features.push_back(std::move(feature));
        }

        return features;
    }

    std::vector<std::vector<double>> pca_reduce(
        const std::vector<std::vector<double>>& features,
        int32_t n_components
    ) {
        constexpr double EPSILON = 1e-10;
        if (features.empty() || n_components <= 0) return features;

        const size_t n_samples = features.size();
        const size_t n_features = features[0].size();
        const size_t n_comp = std::min(static_cast<size_t>(n_components), n_features);

        std::vector<double> mean(n_features, 0.0);
        for (const auto& f : features) {
            for (size_t i = 0; i < n_features; ++i) {
                mean[i] += f[i];
            }
        }
        for (auto& m : mean) {
            m /= static_cast<double>(n_samples);
        }

        std::vector<std::vector<double>> cov(n_features, std::vector<double>(n_features, 0.0));
        for (const auto& f : features) {
            for (size_t i = 0; i < n_features; ++i) {
                for (size_t j = 0; j <= i; ++j) {
                    const double val = (f[i] - mean[i]) * (f[j] - mean[j]);
                    cov[i][j] += val;
                    cov[j][i] += val;
                }
            }
        }

        std::vector<std::vector<double>> reduced(n_samples, std::vector<double>(n_comp, 0.0));

        for (size_t comp = 0; comp < n_comp; ++comp) {
            std::vector<double> eigen_vec(n_features, 1.0 / std::sqrt(static_cast<double>(n_features)));

            for (int iter = 0; iter < 20; ++iter) {
                std::vector<double> new_vec(n_features, 0.0);
                for (size_t i = 0; i < n_features; ++i) {
                    for (size_t j = 0; j < n_features; ++j) {
                        new_vec[i] += cov[i][j] * eigen_vec[j];
                    }
                }
                const double norm = std::sqrt(std::inner_product(new_vec.begin(), new_vec.end(), new_vec.begin(), 0.0));
                if (norm > EPSILON) {
                    for (auto& v : eigen_vec) v /= norm;
                }
            }

            for (size_t s = 0; s < n_samples; ++s) {
                double proj = 0.0;
                for (size_t f = 0; f < n_features; ++f) {
                    proj += (features[s][f] - mean[f]) * eigen_vec[f];
                }
                reduced[s][comp] = proj;
            }

            for (size_t i = 0; i < n_features; ++i) {
                for (size_t j = 0; j < n_features; ++j) {
                    cov[i][j] -= eigen_vec[i] * eigen_vec[j] * n_samples;
                }
            }
        }

        return reduced;
    }

    std::vector<int32_t> kmeans_cluster(
        const std::vector<std::vector<double>>& feature_matrix,
        int32_t k
    ) {
        const size_t n = feature_matrix.size();
        if (n == 0 || k <= 0) return {};

        const size_t n_features = feature_matrix[0].size();
        const int32_t actual_k = std::min(k, static_cast<int32_t>(n));
        std::vector<int32_t> assignments(n, 0);

        std::vector<std::vector<double>> centroids;
        centroids.reserve(actual_k);
        std::vector<double> distances(n, std::numeric_limits<double>::max());
        std::mt19937 gen(random_seed_);

        std::uniform_int_distribution<size_t> dist(0, n - 1);
        centroids.push_back(feature_matrix[dist(gen)]);

        for (int32_t i = 1; i < actual_k; ++i) {
            for (size_t s = 0; s < n; ++s) {
                double min_dist = std::numeric_limits<double>::max();
                for (const auto& c : centroids) {
                    const double d = compute_distance(feature_matrix[s], c);
                    min_dist = std::min(min_dist, d);
                }
                distances[s] = min_dist * min_dist;
            }

            const double total = std::accumulate(distances.begin(), distances.end(), 0.0);
            std::uniform_real_distribution<double> pick_dist(0.0, total > 0 ? total : 1.0);
            double r = pick_dist(gen);
            double cumulative = 0.0;
            size_t sel_idx = 0;
            for (size_t s = 0; s < n; ++s) {
                cumulative += distances[s];
                if (cumulative >= r) {
                    sel_idx = s;
                    break;
                }
            }
            centroids.push_back(feature_matrix[sel_idx]);
        }

        for (int iter = 0; iter < max_iterations_; ++iter) {
            std::vector<std::vector<double>> new_centroids(actual_k, std::vector<double>(n_features, 0.0));
            std::vector<size_t> counts(actual_k, 0);
            bool changed = false;

            for (size_t s = 0; s < n; ++s) {
                int32_t best = 0;
                double best_dist = compute_distance(feature_matrix[s], centroids[0]);
                for (int32_t c = 1; c < actual_k; ++c) {
                    const double d = compute_distance(feature_matrix[s], centroids[c]);
                    if (d < best_dist) {
                        best_dist = d;
                        best = c;
                    }
                }
                if (assignments[s] != best) changed = true;
                assignments[s] = best;
                for (size_t f = 0; f < n_features; ++f) {
                    new_centroids[best][f] += feature_matrix[s][f];
                }
                ++counts[best];
            }

            for (int32_t c = 0; c < actual_k; ++c) {
                if (counts[c] > 0) {
                    for (size_t f = 0; f < n_features; ++f) {
                        centroids[c][f] = new_centroids[c][f] / static_cast<double>(counts[c]);
                    }
                }
            }

            if (!changed) break;
        }

        return assignments;
    }

    std::vector<int32_t> dbscan_cluster(
        const std::vector<std::vector<double>>& feature_matrix,
        double eps,
        int32_t min_samples
    ) {
        const size_t n = feature_matrix.size();
        if (n == 0) return {};

        constexpr int32_t NOISE = -1;
        constexpr int32_t UNVISITED = -2;

        std::vector<int32_t> labels(n, UNVISITED);
        int32_t cluster_id = 0;

        auto region_query = [&](size_t point_idx) -> std::vector<size_t> {
            std::vector<size_t> neighbors;
            const double eps_sq = eps * eps;
            for (size_t j = 0; j < n; ++j) {
                double dist_sq = 0.0;
                for (size_t f = 0; f < feature_matrix[point_idx].size() && f < feature_matrix[j].size(); ++f) {
                    const double diff = feature_matrix[point_idx][f] - feature_matrix[j][f];
                    dist_sq += diff * diff;
                }
                if (dist_sq <= eps_sq) {
                    neighbors.push_back(j);
                }
            }
            return neighbors;
        };

        for (size_t i = 0; i < n; ++i) {
            if (labels[i] != UNVISITED) continue;

            const auto neighbors = region_query(i);
            if (neighbors.size() < static_cast<size_t>(min_samples)) {
                labels[i] = NOISE;
                continue;
            }

            labels[i] = cluster_id;
            for (size_t j = 0; j < neighbors.size(); ++j) {
                const size_t neighbor = neighbors[j];
                if (labels[neighbor] == NOISE) {
                    labels[neighbor] = cluster_id;
                } else if (labels[neighbor] == UNVISITED) {
                    labels[neighbor] = cluster_id;
                    const auto neighbor_neighbors = region_query(neighbor);
                    if (neighbor_neighbors.size() >= static_cast<size_t>(min_samples)) {
                        for (const auto& nn : neighbor_neighbors) {
                            if (labels[nn] == UNVISITED || labels[nn] == NOISE) {
                                if (labels[nn] == UNVISITED) {
                                    labels[nn] = cluster_id;
                                }
                            }
                        }
                    }
                }
            }
            ++cluster_id;
        }

        return labels;
    }

    std::vector<int32_t> hierarchical_cluster(
        const std::vector<std::vector<double>>& feature_matrix,
        int32_t k
    ) {
        const size_t n = feature_matrix.size();
        if (n == 0 || k <= 0) return {};

        const int32_t actual_k = std::min(k, static_cast<int32_t>(n));

        std::vector<std::vector<double>> dist_matrix(n, std::vector<double>(n, 0.0));
        for (size_t i = 0; i < n; ++i) {
            for (size_t j = i + 1; j < n; ++j) {
                dist_matrix[i][j] = dist_matrix[j][i] = compute_distance(feature_matrix[i], feature_matrix[j]);
            }
        }

        std::vector<int32_t> cluster_map(n);
        std::iota(cluster_map.begin(), cluster_map.end(), 0);

        int32_t unique_clusters = static_cast<int32_t>(n);
        while (unique_clusters > actual_k) {
            double min_dist = std::numeric_limits<double>::max();
            size_t merge_i = 0, merge_j = 0;

            for (size_t i = 0; i < n; ++i) {
                for (size_t j = i + 1; j < n; ++j) {
                    if (cluster_map[i] != cluster_map[j] && dist_matrix[i][j] < min_dist) {
                        min_dist = dist_matrix[i][j];
                        merge_i = i;
                        merge_j = j;
                    }
                }
            }

            if (min_dist >= std::numeric_limits<double>::max()) break;

            const int32_t target_cluster = cluster_map[merge_i];
            const int32_t source_cluster = cluster_map[merge_j];

            if (target_cluster == source_cluster) break;

            int32_t merged = 0;
            for (size_t i = 0; i < n; ++i) {
                if (cluster_map[i] == source_cluster) {
                    cluster_map[i] = target_cluster;
                    ++merged;
                }
            }

            unique_clusters -= (merged > 0 ? 1 : 0);

            for (size_t i = 0; i < n; ++i) {
                if (cluster_map[i] == target_cluster) continue;
                double sum = 0.0;
                int count = 0;
                for (size_t j = 0; j < n; ++j) {
                    if (cluster_map[j] == source_cluster) {
                        sum += dist_matrix[i][j];
                        ++count;
                    }
                }
                dist_matrix[i][merge_i] = dist_matrix[merge_i][i] = (count > 0) ? sum / count : min_dist;
            }
        }

        std::unordered_map<int32_t, int32_t> relabel;
        int32_t new_id = 0;
        for (const auto& c : cluster_map) {
            if (!relabel.count(c)) {
                relabel[c] = new_id++;
            }
        }

        for (auto& c : cluster_map) {
            c = relabel[c];
        }

        return cluster_map;
    }

    ClusteringOutput fit(
        const std::vector<ArticleFeature>& articles,
        int32_t algorithm, // 0=kmeans, 1=dbscan, 2=hierarchical
        int32_t n_clusters,
        double eps,
        int32_t min_samples
    ) {
        ClusteringOutput output;
        output.total_articles = static_cast<int32_t>(articles.size());

        if (articles.empty()) return output;

        if (n_clusters <= 0) {
            n_clusters = static_cast<int32_t>(std::sqrt(static_cast<double>(articles.size())));
            if (n_clusters < 1) n_clusters = 1;
        }

        auto features = compute_feature_matrix(articles);
        output.algorithm_used = algorithm == 0 ? "k-means" :
                               algorithm == 1 ? "dbscan" : "hierarchical";

        if (use_pca_) {
            features = pca_reduce(features, static_cast<int32_t>(std::min(size_t(50), features[0].size())));
        }

        std::vector<int32_t> assignments;
        switch (algorithm) {
            case 0: // K_MEANS
                assignments = kmeans_cluster(features, n_clusters);
                break;
            case 1: // DBSCAN
                assignments = dbscan_cluster(features, eps, min_samples);
                break;
            case 2: // HIERARCHICAL
            default:
                assignments = hierarchical_cluster(features, n_clusters);
                break;
        }

        output.assignments = std::move(assignments);

        std::unordered_map<int32_t, int32_t> cluster_counts;
        for (const auto& a : output.assignments) {
            if (a >= 0) ++cluster_counts[a];
        }

        output.total_clusters = static_cast<int32_t>(cluster_counts.size());
        output.clusters.reserve(cluster_counts.size());

        for (const auto& [cid, count] : cluster_counts) {
            ClusterResult cr;
            cr.cluster_id = cid;
            cr.article_count = count;
            cr.distance_to_centroid = 0.0;
            output.clusters.push_back(cr);
        }

        return output;
    }

private:
    int32_t max_iterations_;
    int32_t random_seed_;
    bool use_pca_;
};

struct YallaEventClusterer {
    ClusteringEngine engine;
};

static char* build_cluster_json(
    const std::vector<ArticleFeature>& articles,
    const std::vector<int32_t>& assignments
) {
    json output = json::array();

    std::unordered_map<int32_t, json> cluster_map;
    for (size_t i = 0; i < assignments.size(); ++i) {
        const int32_t cluster_id = assignments[i];
        if (cluster_id < 0) continue;

        json article_json;
        article_json["url"] = articles[i].url;
        article_json["title"] = articles[i].title;
        article_json["keywords"] = articles[i].keywords;
        article_json["category"] = articles[i].category;

        if (!cluster_map.count(cluster_id)) {
            cluster_map[cluster_id] = json{{"cluster_id", cluster_id}, {"articles", json::array()}};
        }
        cluster_map[cluster_id]["articles"].push_back(article_json);
    }

    for (const auto& [_, cluster] : cluster_map) {
        output.push_back(cluster);
    }

    const std::string json_str = output.dump();
    char* result = new char[json_str.length() + 1];
    std::strcpy(result, json_str.c_str());
    return result;
}

extern "C" {

YALLA_CORE_EXPORT YallaEventClustererHandle yalla_event_clusterer_create() {
    return new YallaEventClusterer();
}

YALLA_CORE_EXPORT void yalla_event_clusterer_destroy(YallaEventClustererHandle handle) {
    if (handle) delete static_cast<YallaEventClusterer*>(handle);
}

YALLA_CORE_EXPORT YallaCluster* yalla_event_clusterer_cluster(YallaEventClustererHandle handle,
    const YallaArticle* articles, int32_t article_count, int32_t* cluster_count) {
    if (!handle || !articles || article_count <= 0 || !cluster_count) {
        if (cluster_count) *cluster_count = 0;
        return nullptr;
    }

    auto* clusterer = static_cast<YallaEventClusterer*>(handle);

    // Convert YallaArticle to ArticleFeature
    std::vector<ArticleFeature> features;
    features.reserve(article_count);
    for (int i = 0; i < article_count; ++i) {
        ArticleFeature af;
        af.url = articles[i].url ? articles[i].url : "";
        af.title = articles[i].title ? articles[i].title : "";
        af.content = articles[i].content ? articles[i].content : "";
        af.category = articles[i].category ? articles[i].category : "general";

        if (articles[i].keywords) {
            std::string kw_str(articles[i].keywords);
            std::stringstream ss(kw_str);
            std::string kw;
            while (std::getline(ss, kw, ',')) {
                if (!kw.empty()) af.keywords.push_back(kw);
            }
        }
        features.push_back(std::move(af));
    }

    // Use DBSCAN as default (algorithm=1)
    ClusteringOutput result = clusterer->engine.fit(features, 1, 0, 0.5, 2);

    *cluster_count = static_cast<int32_t>(result.clusters.size());
    if (result.clusters.empty()) return nullptr;

    YallaCluster* c_result = new YallaCluster[result.clusters.size()];
    for (size_t c = 0; c < result.clusters.size(); ++c) {
        c_result[c].cluster_id = result.clusters[c].cluster_id;
        c_result[c].article_count = result.clusters[c].article_count;

        // Collect URLs for this cluster
        std::vector<const char*> urls;
        for (int32_t i = 0; i < article_count; ++i) {
            if (result.assignments[i] == result.clusters[c].cluster_id) {
                const char* url = articles[i].url;
                urls.push_back(url ? strdup(url) : strdup(""));
            }
        }

        c_result[c].article_urls = new const char*[urls.size()];
        for (size_t i = 0; i < urls.size(); ++i) {
            c_result[c].article_urls[i] = urls[i];
        }

        // Build centroid keywords from cluster articles
        std::unordered_map<std::string, int> kw_freq;
        for (int32_t i = 0; i < article_count; ++i) {
            if (result.assignments[i] == result.clusters[c].cluster_id && articles[i].keywords) {
                std::string kw_str(articles[i].keywords);
                std::stringstream ss(kw_str);
                std::string kw;
                while (std::getline(ss, kw, ',')) {
                    if (!kw.empty()) kw_freq[kw]++;
                }
            }
        }

        std::vector<std::pair<int, std::string>> sorted_kws;
        for (const auto& [kw, freq] : kw_freq) {
            sorted_kws.emplace_back(freq, kw);
        }
        std::sort(sorted_kws.rbegin(), sorted_kws.rend());

        std::string centroid_kws;
        for (size_t i = 0; i < std::min(sorted_kws.size(), size_t(10)); ++i) {
            if (i > 0) centroid_kws += ",";
            centroid_kws += sorted_kws[i].second;
        }
        c_result[c].centroid_keywords = strdup(centroid_kws.empty() ? "cluster_keywords" : centroid_kws.c_str());
    }

    return c_result;
}

YALLA_CORE_EXPORT YallaCluster* yalla_event_clusterer_cluster_ex(YallaEventClustererHandle handle,
    const YallaArticle* articles, int32_t article_count, int32_t algorithm,
    int32_t n_clusters, double eps, int32_t min_samples, int32_t* cluster_count) {
    if (!handle || !articles || article_count <= 0 || !cluster_count) {
        if (cluster_count) *cluster_count = 0;
        return nullptr;
    }

    auto* clusterer = static_cast<YallaEventClusterer*>(handle);

    std::vector<ArticleFeature> features;
    features.reserve(article_count);
    for (int i = 0; i < article_count; ++i) {
        ArticleFeature af;
        af.url = articles[i].url ? articles[i].url : "";
        af.title = articles[i].title ? articles[i].title : "";
        af.content = articles[i].content ? articles[i].content : "";
        af.category = articles[i].category ? articles[i].category : "general";

        if (articles[i].keywords) {
            std::string kw_str(articles[i].keywords);
            std::stringstream ss(kw_str);
            std::string kw;
            while (std::getline(ss, kw, ',')) {
                if (!kw.empty()) af.keywords.push_back(kw);
            }
        }
        features.push_back(std::move(af));
    }

    ClusteringOutput result = clusterer->engine.fit(features, algorithm, n_clusters, eps, min_samples);

    *cluster_count = static_cast<int32_t>(result.clusters.size());
    if (result.clusters.empty()) return nullptr;

    YallaCluster* c_result = new YallaCluster[result.clusters.size()];
    for (size_t c = 0; c < result.clusters.size(); ++c) {
        c_result[c].cluster_id = result.clusters[c].cluster_id;
        c_result[c].article_count = result.clusters[c].article_count;

        std::vector<const char*> urls;
        for (int32_t i = 0; i < article_count; ++i) {
            if (result.assignments[i] == result.clusters[c].cluster_id) {
                const char* url = articles[i].url;
                urls.push_back(url ? strdup(url) : strdup(""));
            }
        }

        c_result[c].article_urls = new const char*[urls.size()];
        for (size_t i = 0; i < urls.size(); ++i) {
            c_result[c].article_urls[i] = urls[i];
        }

        std::unordered_map<std::string, int> kw_freq;
        for (int32_t i = 0; i < article_count; ++i) {
            if (result.assignments[i] == result.clusters[c].cluster_id && articles[i].keywords) {
                std::string kw_str(articles[i].keywords);
                std::stringstream ss(kw_str);
                std::string kw;
                while (std::getline(ss, kw, ',')) {
                    if (!kw.empty()) kw_freq[kw]++;
                }
            }
        }

        std::vector<std::pair<int, std::string>> sorted_kws;
        for (const auto& [kw, freq] : kw_freq) {
            sorted_kws.emplace_back(freq, kw);
        }
        std::sort(sorted_kws.rbegin(), sorted_kws.rend());

        std::string centroid_kws;
        for (size_t i = 0; i < std::min(sorted_kws.size(), size_t(10)); ++i) {
            if (i > 0) centroid_kws += ",";
            centroid_kws += sorted_kws[i].second;
        }
        c_result[c].centroid_keywords = strdup(centroid_kws.empty() ? "cluster_keywords" : centroid_kws.c_str());
    }

    return c_result;
}

YALLA_CORE_EXPORT void yalla_event_clusterer_free_clusters(YallaCluster* clusters, int32_t count) {
    if (!clusters) return;
    for (int i = 0; i < count; ++i) {
        if (clusters[i].article_urls) {
            for (int j = 0; j < clusters[i].article_count; ++j) {
                free(const_cast<char*>(clusters[i].article_urls[j]));
            }
            delete[] clusters[i].article_urls;
        }
        free(const_cast<char*>(clusters[i].centroid_keywords));
    }
    delete[] clusters;
}

} // extern "C"