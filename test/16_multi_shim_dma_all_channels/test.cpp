//===- test.cpp -------------------------------------------------*- C++ -*-===//
//
// Copyright (C) 2020-2022, Xilinx Inc.
// Copyright (C) 2022, Advanced Micro Devices, Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//
//===----------------------------------------------------------------------===//

#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <thread>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <xaiengine.h>

#include "air_host.h"

#include "acdc_queue.h"
#include "hsa_defs.h"

#include "aie_inc.cpp"

int
main(int argc, char *argv[])
{
  uint64_t col = 7;
  uint64_t row = 0;

  aie_libxaie_ctx_t *xaie = mlir_aie_init_libxaie();
  mlir_aie_init_device(xaie);

  mlir_aie_configure_cores(xaie);
  mlir_aie_configure_switchboxes(xaie);
  mlir_aie_initialize_locks(xaie);
  mlir_aie_configure_dmas(xaie);
  mlir_aie_start_cores(xaie);

  uint32_t *bram_ptr;

  #define DMA_COUNT 32

  // We're going to stamp over the memories
  for (int i=0; i<DMA_COUNT; i++) {
    mlir_aie_write_buffer_buf72_0(xaie, i, 0xdeadbeef);
    mlir_aie_write_buffer_buf74_0(xaie, i, 0xfeedf00d);
  }
  // create the queue
  queue_t *q = nullptr;
  auto ret = air_queue_create(MB_QUEUE_SIZE, HSA_QUEUE_TYPE_SINGLE, &q, AIR_VCK190_SHMEM_BASE);
  assert(ret == 0 && "failed to create queue!");

  // Let's make a buffer that we can transfer in the same BRAM, after the queue of HSA packets
  int fd = open("/dev/mem", O_RDWR | O_SYNC);
  if (fd == -1)
    return -1;

  bram_ptr = (uint32_t *)mmap(NULL, 0x8000, PROT_READ|PROT_WRITE, MAP_SHARED, fd,  AIR_BBUFF_BASE);
  
  for (int i=0;i<DMA_COUNT;i++) {
    bram_ptr[i] = i;
    bram_ptr[DMA_COUNT+i] = i*2;
    bram_ptr[2*DMA_COUNT+i] = 0x1001ba11; // 50 years of hurt
    bram_ptr[3*DMA_COUNT+i] = 0x10051ade; // Cum on hear the noize
    bram_ptr[4*DMA_COUNT+i] = 0x2001ba11; // 50 years of hurt
    bram_ptr[5*DMA_COUNT+i] = 0x20051ade; // Cum on hear the noize
  }

  uint64_t wr_idx = queue_add_write_index(q, 1);
  uint64_t packet_id = wr_idx % q->size;
  dispatch_packet_t *herd_pkt = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_herd_init(herd_pkt, 0, col, 2, row, 5);
  air_queue_dispatch_and_wait(q, wr_idx, herd_pkt);

  // This starts the copying to the tiles

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_e = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_e, 0, 18, 1, 1, 4, 2, AIR_BBUFF_BASE, DMA_COUNT*sizeof(float), 1, 0, 1, 0, 1, 0);

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_f = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_f, 0, 11, 1, 1, 4, 2, AIR_BBUFF_BASE+(DMA_COUNT*sizeof(float)), DMA_COUNT*sizeof(float), 1, 0, 1, 0, 1, 0);

  // This completes the copying to the tiles, let's move the pattern back

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_g = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_g, 0, 18, 0, 1, 4, 2, AIR_BBUFF_BASE+(4*DMA_COUNT*sizeof(float)), DMA_COUNT*sizeof(float), 1, 0, 1, 0, 1, 0);

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_h = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_h, 0, 11, 0, 1, 4, 2, AIR_BBUFF_BASE+(5*DMA_COUNT*sizeof(float)), DMA_COUNT*sizeof(float), 1, 0, 1, 0, 1, 0);
 
  // This completes packets for first two cores, let's duplicate the effort

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_a = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_a, 0, 18, 1, 0, 4, 2, AIR_BBUFF_BASE, DMA_COUNT*sizeof(float), 1, 0, 1, 0, 1, 0);

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_b = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_b, 0, 11, 1, 0, 4, 2, AIR_BBUFF_BASE+(DMA_COUNT*sizeof(float)), DMA_COUNT*sizeof(float), 1, 0, 1, 0, 1, 0);

  // This completes the copying to the tiles, let's move the pattern back

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_c = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_c, 0, 18, 0, 0, 4, 2, AIR_BBUFF_BASE+(2*DMA_COUNT*sizeof(float)), DMA_COUNT*sizeof(float), 1, 0, 1, 0, 1, 0);

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_d = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_d, 0, 11, 0, 0, 4, 2, AIR_BBUFF_BASE+(3*DMA_COUNT*sizeof(float)), DMA_COUNT*sizeof(float), 1, 0, 1, 0, 1, 0);
  air_queue_dispatch_and_wait(q, wr_idx, pkt_d);

  mlir_aie_print_dma_status(xaie, 7, 2);
  mlir_aie_print_dma_status(xaie, 7, 4);

  uint32_t errs = 0;
  // Let go check the tile memory
  for (int i=0; i<DMA_COUNT; i++) {
    uint32_t d = mlir_aie_read_buffer_buf72_0(xaie, i);
    if (d != i) {
      printf("ERROR: buf72_0 id %d Expected %08X, got %08X\n", i, i, d);
      errs++;
    }
  }
  for (int i=0; i<DMA_COUNT; i++) {
    uint32_t d = mlir_aie_read_buffer_buf74_0(xaie, i);
    if (d != i*2) {
      printf("ERROR: buf74_0 id %d Expected %08X, got %08X\n", i, i*2, d);
      errs++;
    }
  }
  for (int i=0; i<DMA_COUNT; i++) {
    uint32_t d = mlir_aie_read_buffer_buf82_0(xaie, i);
    if (d != i) {
      printf("ERROR: buf82_0 id %d Expected %08X, got %08X\n", i, i, d);
      errs++;
    }
  }
  for (int i=0; i<DMA_COUNT; i++) {
    uint32_t d = mlir_aie_read_buffer_buf84_0(xaie, i);
    if (d != i*2) {
      printf("ERROR: buf84_0 id %d Expected %08X, got %08X\n", i, i*2, d);
      errs++;
    }
  }
  // And the BRAM we updated
  for (int i=0; i<DMA_COUNT; i++) {
    uint32_t d = bram_ptr[2*DMA_COUNT+i];;
    if (d != i) {
      printf("ERROR: buf72_0 copy id %d Expected %08X, got %08X\n", i, i, d);
      errs++;
    }
  }
  for (int i=0; i<DMA_COUNT; i++) {
    uint32_t d = bram_ptr[3*DMA_COUNT+i];;
    if (d != i*2) {
      printf("ERROR: buf74_0 copy id %d Expected %08X, got %08X\n", i, i*2, d);
      errs++;
    }
  }
  for (int i=0; i<DMA_COUNT; i++) {
    uint32_t d = bram_ptr[4*DMA_COUNT+i];;
    if (d != i) {
      printf("ERROR: buf82_0 copy id %d Expected %08X, got %08X\n", i, i, d);
      errs++;
    }
  }
  for (int i=0; i<DMA_COUNT; i++) {
    uint32_t d = bram_ptr[5*DMA_COUNT+i];;
    if (d != i*2) {
      printf("ERROR: buf84_0 copy id %d Expected %08X, got %08X\n", i, i*2, d);
      errs++;
    }
  }

  if (errs == 0) {
    printf("PASS!\n");
    return 0;
  }
  else {
    printf("fail.\n");
    return -1;
  }

}
