#include "hotspot_common.h"
#include "../common/opencl_kernel_common.h"

#define IN_RANGE(x, min, max)   ((x)>=(min) && (x)<=(max))

__attribute__((reqd_work_group_size(BSIZE, BSIZE, 1)))
__attribute__((num_simd_work_items(SIMD)))
__attribute__((num_compute_units(CUSIZE)))
__kernel void hotspot(  int iteration,  //number of iteration *UNUSED*
                        global float * restrict power,   //power input
                        global float * restrict temp_src,    //temperature input/output
                        global float * restrict temp_dst,    //temperature input/output
                        int grid_cols,  //Col of grid
                        int grid_rows,  //Row of grid
                        int border_cols,  // border offset 
                        int border_rows,  // border offset
                        float Cap,      //Capacitance
                        float Rx, 
                        float Ry, 
                        float Rz, 
                        float step) {
	
  local float temp_on_cuda[BSIZE][BSIZE];

  float step_div_Cap;
  float Rx_1,Ry_1,Rz_1;

  int bx = get_group_id(0);
  int by = get_group_id(1);

  int tx = get_local_id(0);
  int ty = get_local_id(1);

  step_div_Cap=step/Cap;

  Rx_1=1/Rx;
  Ry_1=1/Ry;
  Rz_1=1/Rz;

  // each block finally computes result for a small block
  // after N iterations. 
  // it is the non-overlapping small blocks that cover 
  // all the input data

  // calculate the small block size
  int small_block_rows = BSIZE-2;//EXPAND_RATE
  int small_block_cols = BSIZE-2;//EXPAND_RATE

  // calculate the boundary for the block according to 
  // the boundary of its small block
  int blkY = small_block_rows*by-border_rows;
  int blkX = small_block_cols*bx-border_cols;
  int blkYmax = blkY+BSIZE-1;
  int blkXmax = blkX+BSIZE-1;

  // calculate the global thread coordination
  int yidx = blkY+ty;
  int xidx = blkX+tx;

  // load data if it is within the valid input range
  int loadYidx=yidx, loadXidx=xidx;
  int index = grid_cols*loadYidx+loadXidx;
       
  if(IN_RANGE(loadYidx, 0, grid_rows-1) && IN_RANGE(loadXidx, 0, grid_cols-1)){
    temp_on_cuda[ty][tx] = temp_src[index];  // Load the temperature data from global memory to shared memory
  }
  barrier(CLK_LOCAL_MEM_FENCE);

  // effective range within this block that falls within 
  // the valid range of the input data
  // used to rule out computation outside the boundary.
  int validYmin = (blkY < 0) ? -blkY : 0;
  int validYmax = (blkYmax > grid_rows-1) ? BSIZE-1-(blkYmax-grid_rows+1) : BSIZE-1;
  int validXmin = (blkX < 0) ? -blkX : 0;
  int validXmax = (blkXmax > grid_cols-1) ? BSIZE-1-(blkXmax-grid_cols+1) : BSIZE-1;

  int N = ty-1;
  int S = ty+1;
  int W = tx-1;
  int E = tx+1;

  N = (N < validYmin) ? validYmin : N;
  S = (S > validYmax) ? validYmax : S;
  W = (W < validXmin) ? validXmin : W;
  E = (E > validXmax) ? validXmax : E;

  if( IN_RANGE(tx, 1, BSIZE-2) &&  
      IN_RANGE(ty, 1, BSIZE-2) &&
      IN_RANGE(tx, validXmin, validXmax) && 
      IN_RANGE(ty, validYmin, validYmax) ) {
    float new_t = temp_on_cuda[ty][tx] + step_div_Cap *
        (power[index] + 
         (temp_on_cuda[S][tx] + temp_on_cuda[N][tx] - 2.0f * temp_on_cuda[ty][tx]) * Ry_1 + 
         (temp_on_cuda[ty][E] + temp_on_cuda[ty][W] - 2.0f * temp_on_cuda[ty][tx]) * Rx_1 + 
         (AMB_TEMP - temp_on_cuda[ty][tx]) * Rz_1);
    temp_dst[index]= new_t;
  }
}