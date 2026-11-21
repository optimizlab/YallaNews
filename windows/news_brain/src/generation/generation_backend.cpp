#include "yalla_generation_backend.h"

// generation_backend.cpp exists to document that the core holds only the
// IGenerationBackend interface; concrete backends are optional and pluggable.
// The 16 MiB profile loads only the DeterministicWriter.
