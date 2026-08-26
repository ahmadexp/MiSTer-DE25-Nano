// SPDX-License-Identifier: GPL-3.0-or-later
// Write a deterministic 16-row OSD pattern through the DE25 HPS GP bridge.

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define GP_BASE       0x20020000UL
#define GP_MAP_SIZE   0x1000UL
#define GP_OUT_OFFSET 0x00
#define GP_IN_OFFSET  0x10
#define GP_STROBE     (1U << 17)
#define GP_OSD_SELECT (1U << 19)
#define GP_TOP_MASK   0xe0000000U

static volatile uint32_t *gp_out;
static volatile uint32_t *gp_in;

static int wait_ack(uint32_t expected)
{
	for (unsigned int retry = 0; retry < 1000000; ++retry) {
		if ((*gp_in & GP_STROBE) == expected) return 0;
	}
	return -1;
}

static int spi_byte(uint32_t base, uint8_t value)
{
	uint32_t low = base | value;
	*gp_out = low;
	__sync_synchronize();
	*gp_out = low | GP_STROBE;
	__sync_synchronize();
	if (wait_ack(GP_STROBE) < 0) return -1;
	*gp_out = low;
	__sync_synchronize();
	if (wait_ack(0) < 0) return -1;
	return 0;
}

int main(void)
{
	int mem = open("/dev/mem", O_RDWR | O_SYNC);
	if (mem < 0) {
		fprintf(stderr, "open /dev/mem: %s\n", strerror(errno));
		return 1;
	}

	void *mapping = mmap(NULL, GP_MAP_SIZE, PROT_READ | PROT_WRITE,
	                     MAP_SHARED, mem, GP_BASE);
	close(mem);
	if (mapping == MAP_FAILED) {
		fprintf(stderr, "mmap GP bridge: %s\n", strerror(errno));
		return 1;
	}

	gp_out = (volatile uint32_t *)((uint8_t *)mapping + GP_OUT_OFFSET);
	gp_in = (volatile uint32_t *)((uint8_t *)mapping + GP_IN_OFFSET);
	uint32_t saved = *gp_out;
	uint32_t selected = (saved & GP_TOP_MASK) | GP_OSD_SELECT;

	for (unsigned int line = 0; line < 19; ++line) {
		if (spi_byte(selected, (uint8_t)(0x20 | line)) < 0) {
			fprintf(stderr, "OSD handshake timed out on line %u command\n", line);
			goto fail;
		}
		for (unsigned int column = 0; column < 256; ++column) {
			uint8_t value = (((column / 16) + line) & 1) ? 0xff : 0x00;
			if (spi_byte(selected, value) < 0) {
				fprintf(stderr, "OSD handshake timed out on line %u byte %u\n",
				        line, column);
				goto fail;
			}
		}
		*gp_out = selected & ~GP_OSD_SELECT;
		__sync_synchronize();
	}

	if (spi_byte(selected, 0x41) < 0) {
		fprintf(stderr, "OSD enable handshake timed out\n");
		goto fail;
	}
	*gp_out = saved & ~GP_STROBE;
	__sync_synchronize();
	printf("DE25 OSD diagnostic enabled; GP input is 0x%08x\n", *gp_in);
	munmap(mapping, GP_MAP_SIZE);
	return 0;

fail:
	*gp_out = saved & ~GP_STROBE;
	__sync_synchronize();
	munmap(mapping, GP_MAP_SIZE);
	return 1;
}
