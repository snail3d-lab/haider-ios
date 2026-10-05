#include <metal_stdlib>
using namespace metal;

// Composite one frame of the motion field.
//
// Both noise populations share a single ink colour, and that is a correctness
// requirement rather than a style choice: give them different colours and
// P(colour A) = mask * density, so the mask can be read straight off the colour
// proportions of one frame and the whole point collapses. One ink keeps the lit
// density at `density` everywhere.
struct Uniforms {
    uint2 outSize;      // output pixels
    uint2 gridSize;     // dot cells
    uint  dot;          // output pixels per dot cell
    uint  offset;       // scroll in dot cells, already wrapped
    uint  staticBg;     // 1 = only the content scrolls
    uint  qrOn;         // 1 = a QR bias plane is bound
    float4 ink;         // ink colour, linear
    float4 bg;          // background colour
};

static inline uint wrapIdx(int v, int n) {
    return uint(((v % n) + n) % n);
}

kernel void compose(texture2d<uint, access::read>  fore [[texture(0)]],
                    texture2d<uint, access::read>  back [[texture(1)]],
                    texture2d<uint, access::read>  mask [[texture(2)]],
                    texture2d<uint, access::read>  qr   [[texture(4)]],
                    constant Uniforms              &u   [[buffer(0)]],
                    texture2d<float, access::write> out [[texture(3)]],
                    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= u.outSize.x || gid.y >= u.outSize.y) return;

    int cols = int(u.gridSize.x);
    int rows = int(u.gridSize.y);
    int col = int(gid.x / u.dot);
    int row = int(gid.y / u.dot);

    // The up-population scrolls +offset, the down-population -offset. Wrapping
    // at the grid edge keeps the field tiling seamlessly forever.
    int off = int(u.offset);
    uint fRow = wrapIdx(row + off, rows);
    uint bRow = (u.staticBg != 0) ? uint(row) : wrapIdx(row - off, rows);

    uint f = fore.read(uint2(uint(col), fRow)).r;
    uint b = back.read(uint2(uint(col), bRow)).r;
    uint m = mask.read(uint2(uint(col), uint(row))).r;

    uint lit = (m != 0) ? f : b;
    float4 colour = (lit != 0) ? u.ink : u.bg;

    // A QR biased into the field. Cells the plane claims are forced to ink or
    // paper, which is what makes the module's MEAN land on the right side of a
    // reader's threshold -- the code scans from any single frame while the rest
    // of the field keeps scrolling, and nothing is drawn over the field.
    if (u.qrOn != 0) {
        // The plane scrolls at half speed so it never looks pasted on.
        int qOff = off / 2;
        uint qRow = wrapIdx(row + qOff, rows);
        uint q = qr.read(uint2(uint(col), qRow)).r;
        if (q == 1)      colour = u.ink;
        else if (q == 2) colour = u.bg;
    }
    out.write(colour, gid);
}