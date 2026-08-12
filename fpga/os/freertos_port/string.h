#ifndef H3_FREERTOS_STRING_H
#define H3_FREERTOS_STRING_H

#include <stddef.h>

void * memset( void * dst, int value, size_t len );
void * memcpy( void * dst, const void * src, size_t len );

#endif
