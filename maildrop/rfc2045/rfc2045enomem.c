#if	HAVE_CONFIG_H
#include       "config.h"
#endif
#include	"rfc2045.h"
void rfc2045_enomem(void);

void rfc2045_enomem(void)
{
	rfc2045_error("Out of memory.");
}
