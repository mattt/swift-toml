#define TOML_HEADER_ONLY 1
// Disable assertions to handle invalid input gracefully
#define NDEBUG 1
#include "include/ctoml.h"
#include "toml.hpp"
#include <cstdlib>
#include <cstring>
#include <list>
#include <new>
#include <string>
#include <string_view>
#include <vector>

// Forward declaration
static CTomlNode convert_node(const toml::node& node, struct CTomlTable* storage);

// Internal storage class to hold all allocated memory
struct CTomlTable
{
	// Use std::list instead of std::vector because list doesn't invalidate
	// pointers when growing (vector reallocation would invalidate string
	// pointers)
	std::list<std::string> strings;
	std::vector<void*> allocations; // Generic pointer storage
	std::string error_message;

	// Store a string and return a persistent CTomlString with length
	CTomlString store_string(const std::string& s)
	{
		strings.push_back(s);
		const auto& stored = strings.back();
		return CTomlString{ stored.c_str(), stored.size() };
	}

	// Allocate an array of nodes
	CTomlNode* alloc_nodes(size_t count)
	{
		if (count == 0)
			return nullptr;
		void* mem = std::malloc(count * sizeof(CTomlNode));
		if (!mem)
		{
			throw std::bad_alloc();
		}
		allocations.push_back(mem);
		return static_cast<CTomlNode*>(mem);
	}

	// Allocate an array of CTomlString keys
	CTomlString* alloc_keys(size_t count)
	{
		if (count == 0)
			return nullptr;
		void* mem = std::malloc(count * sizeof(CTomlString));
		if (!mem)
		{
			throw std::bad_alloc();
		}
		allocations.push_back(mem);
		return static_cast<CTomlString*>(mem);
	}

	~CTomlTable()
	{
		for (void* ptr : allocations)
		{
			std::free(ptr);
		}
	}
};

static CTomlNode convert_table(const toml::table& table, CTomlTable* storage)
{
	CTomlNode result;
	result.type = CTOML_TABLE;

	size_t count = table.size();

	result.data.table_value.count  = count;
	result.data.table_value.keys   = storage->alloc_keys(count);
	result.data.table_value.values = storage->alloc_nodes(count);

	size_t i = 0;
	for (auto& [k, v] : table)
	{
		result.data.table_value.keys[i]	  = storage->store_string(std::string(k));
		result.data.table_value.values[i] = convert_node(v, storage);
		i++;
	}

	return result;
}

static CTomlNode convert_array(const toml::array& arr, CTomlTable* storage)
{
	CTomlNode result;
	result.type = CTOML_ARRAY;

	size_t count					 = arr.size();
	result.data.array_value.count	 = count;
	result.data.array_value.elements = storage->alloc_nodes(count);

	for (size_t i = 0; i < count; ++i)
	{
		if (auto* elem = arr.get(i))
		{
			result.data.array_value.elements[i] = convert_node(*elem, storage);
		}
		else
		{
			CTomlNode none_node{};
			none_node.type						= CTOML_NONE;
			result.data.array_value.elements[i] = none_node;
		}
	}

	return result;
}

static CTomlNode convert_node(const toml::node& node, CTomlTable* storage)
{
	CTomlNode result;
	result.type = CTOML_NONE;

	if (node.is_string())
	{
		result.type				 = CTOML_STRING;
		result.data.string_value = storage->store_string(std::string(node.as_string()->get()));
	}
	else if (node.is_integer())
	{
		result.type				  = CTOML_INTEGER;
		result.data.integer_value = node.as_integer()->get();
	}
	else if (node.is_floating_point())
	{
		result.type				= CTOML_FLOAT;
		result.data.float_value = node.as_floating_point()->get();
	}
	else if (node.is_boolean())
	{
		result.type				  = CTOML_BOOLEAN;
		result.data.boolean_value = node.as_boolean()->get();
	}
	else if (node.is_date())
	{
		result.type					 = CTOML_DATE;
		auto d						 = node.as_date()->get();
		result.data.date_value.year	 = d.year;
		result.data.date_value.month = static_cast<int32_t>(d.month);
		result.data.date_value.day	 = static_cast<int32_t>(d.day);
	}
	else if (node.is_time())
	{
		result.type						  = CTOML_TIME;
		auto t							  = node.as_time()->get();
		result.data.time_value.hour		  = static_cast<int32_t>(t.hour);
		result.data.time_value.minute	  = static_cast<int32_t>(t.minute);
		result.data.time_value.second	  = static_cast<int32_t>(t.second);
		result.data.time_value.nanosecond = static_cast<int32_t>(t.nanosecond);
	}
	else if (node.is_date_time())
	{
		result.type								   = CTOML_DATETIME;
		auto dt									   = node.as_date_time()->get();
		result.data.datetime_value.date.year	   = dt.date.year;
		result.data.datetime_value.date.month	   = static_cast<int32_t>(dt.date.month);
		result.data.datetime_value.date.day		   = static_cast<int32_t>(dt.date.day);
		result.data.datetime_value.time.hour	   = static_cast<int32_t>(dt.time.hour);
		result.data.datetime_value.time.minute	   = static_cast<int32_t>(dt.time.minute);
		result.data.datetime_value.time.second	   = static_cast<int32_t>(dt.time.second);
		result.data.datetime_value.time.nanosecond = static_cast<int32_t>(dt.time.nanosecond);
		result.data.datetime_value.has_offset	   = dt.offset.has_value();
		result.data.datetime_value.offset_minutes  = result.data.datetime_value.has_offset ? dt.offset->minutes : 0;
	}
	else if (node.is_array())
	{
		return convert_array(*node.as_array(), storage);
	}
	else if (node.is_table())
	{
		return convert_table(*node.as_table(), storage);
	}

	return result;
}

extern "C"
{
	CTomlParseResult ctoml_parse(const char* input, size_t length)
	{
		CTomlParseResult result;
		result.success		 = false;
		result.error_message = nullptr;
		result.error_line	 = 0;
		result.error_column	 = 0;
		result.handle		 = nullptr;
		result.root.type	 = CTOML_NONE;

		try
		{
			CTomlTable* storage = new CTomlTable();
			result.handle		= storage;

			std::string_view sv(input, length);
			auto table	   = toml::parse(sv);
			result.root	   = convert_table(table, storage);
			result.success = true;
		}
		catch (const toml::parse_error& err)
		{
			if (result.handle)
			{
				result.handle->error_message = std::string(err.description());
				result.error_message		 = result.handle->error_message.c_str();
			}
			result.error_line	= err.source().begin.line;
			result.error_column = err.source().begin.column;
			result.root.type	= CTOML_NONE;
		}
		catch (const std::exception& err)
		{
			if (result.handle)
			{
				result.handle->error_message = std::string(err.what());
				result.error_message		 = result.handle->error_message.c_str();
			}
			else
			{
				// Best effort if allocation failed before we created a handle.
				if (dynamic_cast<const std::bad_alloc*>(&err))
				{
					result.error_message = "Out of memory";
				}
				else
				{
					result.error_message = "Unknown error";
				}
			}
			result.error_line	= 0;
			result.error_column = 0;
			result.root.type	= CTOML_NONE;
		}
		catch (...)
		{
			if (result.handle)
			{
				result.handle->error_message = "Unknown error";
				result.error_message		 = result.handle->error_message.c_str();
			}
			else
			{
				result.error_message = "Unknown error";
			}
			result.error_line	= 0;
			result.error_column = 0;
			result.root.type	= CTOML_NONE;
		}

		return result;
	}

	void ctoml_free_result(CTomlParseResult* result)
	{
		if (!result)
		{
			return;
		}

		if (result->handle)
		{
			delete result->handle;
			result->handle = nullptr;
		}

		// Invalidate all other fields to avoid dangling pointers after free.
		result->error_message = nullptr;
		result->success		  = false;
		result->error_line	  = 0;
		result->error_column  = 0;

		// Clear root node, which may contain pointers into freed storage.
		std::memset(&result->root, 0, sizeof(result->root));
		result->root.type = CTOML_NONE;
	}

} // extern "C"
