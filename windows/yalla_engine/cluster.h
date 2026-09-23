#ifndef YALLA_CLUSTER_H
#define YALLA_CLUSTER_H

#include <string>
#include <vector>
#include <memory>
#include <cstdint>

#ifdef _WIN32
  #define YALLA_CLUSTER_EXPORT __declspec(dllexport)
#else
  #define YALLA_CLUSTER_EXPORT __attribute__((visibility("default")))
#endif

struct ArticleFeature {
    std::string url;
    std::string title;
    std::vector<std::string> keywords;
    std::vector<float> embedding;
    std::string content;
    std::string category;
};

struct ClusterResult {
    int32_t cluster_id;
    double distance_to_centroid;
    int32_t article_count;
};

struct ClusteringOutput {
    std::vector<ClusterResult> clusters;
    std::vector<int32_t> assignments;
    std::string algorithm_used;
    int32_t total_articles;
    int32_t total_clusters;
};

enum class ClusterAlgorithm {
    K_MEANS,
    DBSCAN,
    HIERARCHICAL
};

class ClusteringEngine {
public:
    ClusteringEngine() = default;
    ~ClusteringEngine() = default;

    ClusteringOutput fit(
        const std::vector<ArticleFeature>& articles,
        ClusterAlgorithm algorithm = ClusterAlgorithm::DBSCAN,
        int32_t n_clusters = 0,
        double eps = 0.5,
        int32_t min_samples = 2
    );

    void set_random_seed(uint32_t seed) { random_seed_ = seed; }
    void enable_pca_reduction(bool enable) { use_pca_ = enable; }
    void set_max_iterations(int32_t max_iter) { max_iterations_ = max_iter; }
    void set_distance_metric(int32_t metric) { distance_metric_ = metric; }

private:
    std::vector<std::vector<double>> compute_feature_matrix(
        const std::vector<ArticleFeature>& articles
    );

    double compute_distance(const std::vector<double>& a, const std::vector<double>& b) const;
    std::vector<int32_t> kmeans_cluster(
        const std::vector<std::vector<double>>& feature_matrix,
        int32_t k
    );
    std::vector<int32_t> dbscan_cluster(
        const std::vector<std::vector<double>>& feature_matrix,
        double eps,
        int32_t min_samples
    );
    std::vector<int32_t> hierarchical_cluster(
        const std::vector<std::vector<double>>& feature_matrix,
        int32_t k
    );

    std::vector<std::vector<double>> pca_reduce(
        const std::vector<std::vector<double>>& features,
        int32_t n_components
    );

    uint32_t random_seed_ = 42;
    bool use_pca_ = true;
    int32_t max_iterations_ = 100;
    int32_t distance_metric_ = 0;
};

extern "C" {
    const char* cluster_articles(const char* json_input);
    const char* cluster_articles_ex(
        const char* json_input,
        int32_t algorithm,
        int32_t n_clusters,
        double eps,
        int32_t min_samples
    );
    void free_cluster_string(const char* str);
}

#endif // YALLA_CLUSTER_H