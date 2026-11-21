#ifndef YALLA_ENTITY_ENGINE_H
#define YALLA_ENTITY_ENGINE_H

#include "core/job_context.h"
#include "yalla_editorial.h"

#include <string>
#include <vector>

namespace yalla {

// EntityEngine identifies and normalizes people, organizations, places, etc.
// Original spellings and canonical forms are preserved. Names from different
// languages are not merged merely because they look similar.
class EntityEngine {
public:
    explicit EntityEngine(JobContext& job);

    std::vector<Entity> extract_entities(const std::string& title,
                                         const std::string& body,
                                         const std::string& language) const;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_ENTITY_ENGINE_H
