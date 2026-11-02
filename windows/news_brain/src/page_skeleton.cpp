#include "../include/page_skeleton.h"

namespace newsbrain {

nlohmann::json PageSkeleton::toJson() const {
    nlohmann::json root;
    root["url"] = url;
    root["canonicalUrl"] = canonicalUrl;

    // Metadata
    nlohmann::json meta;
    meta["title"] = metadata.title;
    meta["description"] = metadata.description;
    meta["canonicalUrl"] = metadata.canonicalUrl;
    meta["author"] = metadata.author;
    meta["publishDate"] = metadata.publishDate;
    meta["language"] = metadata.language;
    meta["siteName"] = metadata.siteName;
    meta["ogTitle"] = metadata.ogTitle;
    meta["ogDescription"] = metadata.ogDescription;
    meta["ogImage"] = metadata.ogImage;
    meta["ogType"] = metadata.ogType;
    meta["schemaType"] = metadata.schemaType;
    meta["jsonLd"] = metadata.jsonLd;
    
    nlohmann::json ogMap = nlohmann::json::object();
    for (const auto& kv : metadata.openGraph) {
        ogMap[kv.first] = kv.second;
    }
    meta["openGraph"] = ogMap;
    root["metadata"] = meta;

    // Nodes
    nlohmann::json nodeArray = nlohmann::json::array();
    for (const auto& n : nodes) {
        nlohmann::json jn;
        jn["id"] = n.id;
        jn["type"] = nodeTypeToString(n.type);
        jn["depth"] = n.depth;
        jn["parent"] = n.parent;
        jn["tag"] = n.tag;
        jn["role"] = n.role;
        jn["className"] = n.className;
        jn["idAttr"] = n.idAttr;
        jn["text"] = n.text;
        jn["textLength"] = n.textLength;
        jn["linkCount"] = n.linkCount;
        jn["imageCount"] = n.imageCount;
        jn["linkDensity"] = n.linkDensity;
        jn["textDensity"] = n.textDensity;
        jn["contentScore"] = n.contentScore;
        jn["isGarbage"] = n.isGarbage;

        nlohmann::json chList = nlohmann::json::array();
        for (NodeId ch : n.children) {
            chList.push_back(ch);
        }
        jn["children"] = chList;

        nodeArray.push_back(jn);
    }
    root["nodes"] = nodeArray;

    // Images
    nlohmann::json imgArray = nlohmann::json::array();
    for (const auto& img : images) {
        nlohmann::json ji;
        ji["src"] = img.src;
        ji["alt"] = img.alt;
        ji["caption"] = img.caption;
        ji["width"] = img.width;
        ji["height"] = img.height;
        ji["nodeId"] = img.nodeId;
        ji["relevanceScore"] = img.relevanceScore;
        ji["isLead"] = img.isLead;
        imgArray.push_back(ji);
    }
    root["images"] = imgArray;

    // Candidates
    nlohmann::json candArray = nlohmann::json::array();
    for (const auto& c : candidates) {
        nlohmann::json jc;
        jc["candidateId"] = c.candidateId;
        jc["rootNodeId"] = c.rootNodeId;
        jc["score"] = c.score;
        jc["nodeCount"] = c.nodeCount;
        jc["textLength"] = c.textLength;
        jc["paragraphCount"] = c.paragraphCount;
        jc["imageCount"] = c.imageCount;
        jc["linkCount"] = c.linkCount;
        jc["linkDensity"] = c.linkDensity;
        jc["previewText"] = c.previewText;

        nlohmann::json memList = nlohmann::json::array();
        for (NodeId m : c.memberNodeIds) {
            memList.push_back(m);
        }
        jc["memberNodeIds"] = memList;

        candArray.push_back(jc);
    }
    root["candidates"] = candArray;

    return root;
}

} // namespace newsbrain
