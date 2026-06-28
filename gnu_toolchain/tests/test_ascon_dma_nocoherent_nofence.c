/* Negative control for coherent no-fence test.
 * Same firmware flow, but DMA coherence is disabled. */
#define DMA_COH_CTRL_VALUE 0u
#include "test_ascon_dma_coherent_nofence.c"
