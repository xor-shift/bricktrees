#pragma endian little

#pragma array_limit 262144

import std.mem;

namespace qov {
  struct Header {
    char magic[4];
    u8 version_major;
    u8 version_minor;
    u32 segment_count;
  };

  enum SegmentType : u8 {
    raw = 0,
    rle = 1,
    qoi = 2,
  };

  enum CurveType : u8 {
    raster = 0,
    morton = 1,
    hilbert = 2,
  };

  namespace segments {

  struct Raw {
    u32 voxels[64 * 64 * 64];
  };

  
  u64 rle_counter = 0;  
  struct RLEOp {
    u16 length;
    if (length == 0) {
      u32 voxel;
      rle_counter += 1;
    } else {
      rle_counter += length;
    }
  };

  struct RLE {
    rle_counter = 0;
    RLEOp rle_ops[while(rle_counter != 64 * 64 * 64)];
  };
}

struct Segment {
  u64 segment_coords[3];
  SegmentType segment_type;
  CurveType curve_type;
  if      (segment_type == SegmentType::raw) segments::Raw;
  else if (segment_type == SegmentType::rle) segments::RLE;
};

struct File {
  Header header;
  Segment segments[header.segment_count];
};

}

qov::File file @ 0x0;
