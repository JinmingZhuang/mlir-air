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

#define BRAM_ADDR AIR_BBUFF_BASE

#include "aie_inc.cpp"

// test configuration
#define IMAGE_WIDTH 128
#define IMAGE_HEIGHT 16
#define IMAGE_SIZE  (IMAGE_WIDTH * IMAGE_HEIGHT)

#define TILE_WIDTH 16
#define TILE_HEIGHT 8
#define TILE_SIZE  (TILE_WIDTH * TILE_HEIGHT)

#define NUM_3D (IMAGE_WIDTH / TILE_WIDTH)
#define NUM_4D (IMAGE_HEIGHT / TILE_HEIGHT)

int
main(int argc, char *argv[])
{
  uint64_t col = 7;
  uint64_t row = 0;

  aie_libxaie_ctx_t *xaie = mlir_aie_init_libxaie();
  mlir_aie_init_device(xaie);

  mlir_aie_print_dma_status(xaie, 7, 2);

  mlir_aie_configure_cores(xaie);
  mlir_aie_configure_switchboxes(xaie);
  mlir_aie_initialize_locks(xaie);
  mlir_aie_configure_dmas(xaie);
  mlir_aie_start_cores(xaie);

  // setup images in memory
  uint32_t *bram_ptr;

  int fd = open("/dev/mem", O_RDWR | O_SYNC);
  if (fd != -1) {
    bram_ptr = (uint32_t *)mmap(NULL, 0x8000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, BRAM_ADDR);
    for (int i=0; i<IMAGE_SIZE; i++) {
      bram_ptr[i] = i+1;
      bram_ptr[IMAGE_SIZE+i] = 1;
      bram_ptr[2*IMAGE_SIZE+i] = 0xdeface;
    }
  } else return -1;

  // stamp over the aie tiles
  for (int i=0; i<TILE_SIZE; i++) {
    mlir_aie_write_buffer_ping_a(xaie, i, 0xabba0000+i);
    mlir_aie_write_buffer_pong_a(xaie, i, 0xdeeded00+i);
    mlir_aie_write_buffer_ping_b(xaie, i, 0xcafe0000+i);
    mlir_aie_write_buffer_pong_b(xaie, i, 0xfabcab00+i);
    mlir_aie_write_buffer_ping_c(xaie, i, 0x12345670+i);
    mlir_aie_write_buffer_pong_c(xaie, i, 0x76543210+i);
  }

  // create the queue
  queue_t *q = nullptr;
  auto ret = air_queue_create(MB_QUEUE_SIZE, HSA_QUEUE_TYPE_SINGLE, &q, AIR_VCK190_SHMEM_BASE);
  assert(ret == 0 && "failed to create queue!");

  // setup the herd
  uint64_t wr_idx = queue_add_write_index(q, 1);
  uint64_t packet_id = wr_idx % q->size;
  dispatch_packet_t *herd_pkt = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_herd_init(herd_pkt, 0, col, 1, row, 3);
  air_queue_dispatch_and_wait(q, wr_idx, herd_pkt);

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *shim_pkt = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_device_init(shim_pkt,XAIE_NUM_COLS);
  air_queue_dispatch_and_wait(q, wr_idx, shim_pkt);

  //
  // packet to read the data
  //

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_c = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_c, 0, col, 0, 0, 4, 2, BRAM_ADDR+(2*IMAGE_SIZE*sizeof(float)), TILE_WIDTH*sizeof(float), TILE_HEIGHT, IMAGE_WIDTH*sizeof(float), NUM_3D, TILE_WIDTH*sizeof(float), NUM_4D, IMAGE_WIDTH*TILE_HEIGHT*sizeof(float));

  //
  // packet to send the data
  //

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_a = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_a, 0, col, 1, 0, 4, 2, BRAM_ADDR, TILE_WIDTH*sizeof(float), TILE_HEIGHT, IMAGE_WIDTH*sizeof(float), NUM_3D, TILE_WIDTH*sizeof(float), NUM_4D, IMAGE_WIDTH*TILE_HEIGHT*sizeof(float));

  wr_idx = queue_add_write_index(q, 1);
  packet_id = wr_idx % q->size;
  dispatch_packet_t *pkt_b = (dispatch_packet_t*)(q->base_address_vaddr) + packet_id;
  air_packet_nd_memcpy(pkt_b, 0, col, 1, 1, 4, 2, BRAM_ADDR+(IMAGE_SIZE*sizeof(float)), TILE_WIDTH*sizeof(float), TILE_HEIGHT, IMAGE_WIDTH*sizeof(float), NUM_3D, TILE_WIDTH*sizeof(float), NUM_4D, IMAGE_WIDTH*TILE_HEIGHT*sizeof(float));

  //
  // dispatch the packets to the MB
  //

  air_queue_dispatch_and_wait(q, wr_idx-2, pkt_c);

  int errors = 0;
  // check the aie tiles
  for (int i=0; i<TILE_SIZE; i++) {
    uint32_t d0 = mlir_aie_read_buffer_ping_a(xaie, i);
    uint32_t d1 = mlir_aie_read_buffer_pong_a(xaie, i);
    uint32_t d4 = mlir_aie_read_buffer_ping_b(xaie, i);
    uint32_t d5 = mlir_aie_read_buffer_pong_b(xaie, i);
    uint32_t d2 = mlir_aie_read_buffer_ping_c(xaie, i);
    uint32_t d3 = mlir_aie_read_buffer_pong_c(xaie, i);
    if (d0+d4 != d2) {
      printf("mismatch [%d] ping %x+%x != %x\n", i, d0, d4, d2);
      errors++;
    }
    if (d1+d5 != d3) {
      printf("mismatch [%d] pong %x+%x != %x\n", i, d1, d5, d3);
      errors++;
    }
  }

  // check the output image
  for (int i=0; i<IMAGE_SIZE; i++) {
    uint32_t d = bram_ptr[2*IMAGE_SIZE+i];
    if (d != (i+2)) {
      errors++;
      printf("mismatch %x != 2 + %x\n", d, i);
    }
  }
  if (!errors) {
    printf("PASS!\n");
    return 0;
  }
  else {
    printf("fail %d/%d.\n", errors, IMAGE_SIZE+2*TILE_SIZE);
    return -1;
  }

}