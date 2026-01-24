#ifndef CTOML_H
#define CTOML_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle type (hides C++ implementation)
typedef struct CTomlTable CTomlTable;

// Node types enum
typedef enum {
    CTOML_NONE = 0,
    CTOML_STRING,
    CTOML_INTEGER,
    CTOML_FLOAT,
    CTOML_BOOLEAN,
    CTOML_DATE,
    CTOML_TIME,
    CTOML_DATETIME,
    CTOML_ARRAY,
    CTOML_TABLE
} CTomlNodeType;

// Date/Time structures
typedef struct {
    int32_t year;
    int32_t month;
    int32_t day;
} CTomlDate;

typedef struct {
    int32_t hour;
    int32_t minute;
    int32_t second;
    int32_t nanosecond;
} CTomlTime;

typedef struct {
    CTomlDate date;
    CTomlTime time;
    bool has_offset;
    int32_t offset_minutes;
} CTomlDateTime;

// Forward declaration for self-referential types
struct CTomlNode;

// Array data structure
typedef struct {
    struct CTomlNode* elements;
    size_t count;
} CTomlArrayData;

// Table data structure
typedef struct {
    const char** keys;
    struct CTomlNode* values;
    size_t count;
} CTomlTableData;

// Node value union - holds the actual data
typedef struct CTomlNode {
    CTomlNodeType type;
    union {
        const char* string_value;
        int64_t integer_value;
        double float_value;
        bool boolean_value;
        CTomlDate date_value;
        CTomlTime time_value;
        CTomlDateTime datetime_value;
        CTomlArrayData array_value;
        CTomlTableData table_value;
    } data;
} CTomlNode;

// Parse result structure
typedef struct {
    bool success;
    CTomlNode root;
    // Error information (only valid if success == false)
    const char* error_message;
    int64_t error_line;
    int64_t error_column;
    // Internal handle for memory management
    CTomlTable* _handle;
} CTomlParseResult;

// Parsing
CTomlParseResult ctoml_parse(const char* input, size_t length);
void ctoml_free_result(CTomlParseResult* result);

#ifdef __cplusplus
}
#endif

#endif // CTOML_H
