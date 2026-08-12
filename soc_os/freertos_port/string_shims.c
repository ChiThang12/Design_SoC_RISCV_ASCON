#include <stddef.h>

void * memset( void * dst, int value, size_t len )
{
    unsigned char * d = ( unsigned char * ) dst;
    unsigned char v = ( unsigned char ) value;

    while( len-- != 0u )
    {
        *d++ = v;
    }

    return dst;
}

void * memcpy( void * dst, const void * src, size_t len )
{
    unsigned char * d = ( unsigned char * ) dst;
    const unsigned char * s = ( const unsigned char * ) src;

    while( len-- != 0u )
    {
        *d++ = *s++;
    }

    return dst;
}
