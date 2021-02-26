#define EPS 0.000005f    // Ray epsilon and exit offset
#define OFFSET 0.0001f   // TODO: refine these values?

// General arguments. Remove unnecessary arguments and add extra arguments in <data>:
// float3 *origin, float3 *direction, float3 *normal, float4 *color, float3 *emittance, float *distance, <data>, unsigned int *random
// Data should be grouped logically ie. if the octree is passed, (image2d_t) octreeData, (int) depth
// All mutable vectors should be pointers, even if the current function does not need to modify it

// Sky calculations
void calcSkyRay(float3 *direction, float4 *color, float3 *emittance, image2d_t skyTexture, float3 sunPos, float sunIntensity, image2d_t textures, int sunIndex);
void sunIntersect(float3 *direction, float4 *color, float3 *emittance, float3 sunPos, image2d_t textures, int sunIndex);

// Octree calculations
void getTextureRay(float3 *origin, float3 *normal, float4 *color, float3 *emittance, int block, image2d_t textures, image1d_t blockData, image2d_t grassTextures, image2d_t foliageTextures, int depth);
int octreeIntersect(float3 *origin, image2d_t octreeData, int depth, __global const int *transparent, int transparentLength);
int octreeGet(float3 *origin, image2d_t octreeData, int depth);
int octreeInbounds(float3 *origin, int depth);
void exitBlock(float3 *origin, float3 *direction, float3 *normal, float *distance);

// Entity calculations
int entityIntersect(float3 *origin, float3 *direction, float3 *normal, float4 *color, float3 *emittance, float *distance, image2d_t entityData, image2d_t entityTrigs, image2d_t entityTextures);
int texturedTriangleIntersect(float3 *origin, float3 *direction, float3 *normal, float4 *color, float3 *emittance, float *distance, int index, image2d_t entityTrigs, image2d_t entityTextures);
int aabbIntersect(float3 *origin, float3 *direction, float bounds[6]);
int aabbIntersectClose(float3 *origin, float3 *direction, float *distance, float bounds[6]);
int aabbInside(float3 *origin, float bounds[6]);

// Reflection calculations
void diffuseReflect(float3 *direction, float3 *normal, unsigned int *state);

// Texture read functions
float indexf(image2d_t img, int index);
int indexi(image2d_t img, int index);
unsigned int indexu(image2d_t img, int index);

// Texture read array functions
void areadf(image2d_t img, int index, int length, float output[]);
void areadi(image2d_t img, int index, int length, int output[]);
void areadu(image2d_t img, int index, int length, unsigned int output[]);

// Samplers
const sampler_t indexSampler = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_NEAREST;
const sampler_t skySampler =   CLK_NORMALIZED_COORDS_TRUE  | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_LINEAR;

// Randomness
void xorshift(unsigned int *state);
float nextFloat(unsigned int *state);

// Ray tracer entrypoint
__kernel void rayTracer(__global const float *rayPos,
                        __global const float *rayDir,
                        __global const int *depth,
                        image2d_t octreeData,
                        __global const int *voxelLength,
                        __global const int *transparent,
                        __global const int *transparentLength,
                        image2d_t textures,
                        image1d_t blockData,
                        __global const int *seed,
                        __global const int *rayDepth,
                        __global const int *preview,
                        __global const float *sunPos,
                        __global const int *sunIndex,
                        __global const float *sunIntensity,
                        image2d_t skyTexture,
                        image2d_t grassTextures,
                        image2d_t foliageTextures,
                        image2d_t entityData,
                        image2d_t entityTrigs,
                        image2d_t entityTextures,
                        __global const int *drawEntities,
                        __global const int *drawDepth,
                        __global float *res)
{
    int gid = get_global_id(0);

    // Initialize rng
    unsigned int rngState = *seed + gid;
    unsigned int *random = &rngState;
    xorshift(random);
    xorshift(random);

    // Ray origin
    float3 origin = (float3) (rayPos[0], rayPos[1], rayPos[2]);

    // Ray direction
    float3 direction = (float3) (
            rayDir[gid*3 + 0],
            rayDir[gid*3 + 1],
            rayDir[gid*3 + 2]
    );

    // Ray normal
    float3 normal = (float3) (0, 0, 0);

    // Sun position
    float3 sunPosition = (float3) (sunPos[0], sunPos[1], sunPos[2]);

    // temp array
    float3 temp;

    // Jitter each ray randomly
    // TODO: Pass the jitter amount as an argument?
    temp = (float3) (rayDir[gid*3 + 3], rayDir[gid*3 + 4], rayDir[gid*3 + 5]);
    temp -= direction;

    float jitter = length(temp);

    direction.x += nextFloat(random) * jitter;
    direction.y += nextFloat(random) * jitter;
    direction.z += nextFloat(random) * jitter;
    direction = normalize(direction);

    // Cap max bounces at 23 since no dynamic memory allocation
    int maxbounces = *rayDepth;
    if (maxbounces > 23) maxbounces = 23;

    // Ray bounce data stacks
    float colorStack[3 * 24] = {0};
    float emittanceStack[3 * 24] = {0};
    int typeStack[24];

    // Do the bounces
    float distance = 0;
    for (int bounces = 0; bounces < maxbounces; bounces++)
    {
        float3 originStart = (float3) (origin.x, origin.y, origin.z);
        int hit = 0;
        float4 color = (float4) (0, 0, 0, 1);
        float3 emittance = (float3) (0, 0, 0);

        // Ray march
        for (int i = 0; i < *drawDepth; i++) {
            if (!octreeIntersect(&origin, octreeData, *depth, transparent, *transparentLength))
                exitBlock(&origin, &direction, &normal, &distance);
            else {
                hit = 1;
                break;
            }

            if (!octreeInbounds(&origin, *depth))
                break;
        }

        // Set color to sky color or texture color
        if (hit) {
            int block = octreeGet(&origin, octreeData, *depth);
            getTextureRay(&origin, &normal, &color, &emittance, block, textures, blockData, grassTextures, foliageTextures, *depth);
        } else {
            calcSkyRay(&direction, &color, &emittance, skyTexture, sunPosition, *sunIntensity, textures, *sunIndex);
        }

        // BVH intersection
        if (*drawEntities) {
            if (entityIntersect(&origin, &direction, &normal, &color, &emittance, &distance, entityData, entityTrigs, entityTextures)) {
                hit = 1;

                origin = originStart;
                origin += direction * distance;
            }
        }

        // Exit on sky hit
        if (!hit) {
            float sunScale = pow(*sunIntensity, 2.2f);

            emittanceStack[bounces*3 + 0] = color.x * sunScale;
            emittanceStack[bounces*3 + 1] = color.y * sunScale;
            emittanceStack[bounces*3 + 2] = color.z * sunScale;

            emittanceStack[bounces*3 + 3] = color.x * sunScale;
            emittanceStack[bounces*3 + 4] = color.y * sunScale;
            emittanceStack[bounces*3 + 5] = color.z * sunScale;

            // Set color stack to sky color
            for (int i = bounces; i < maxbounces; i++) {
                colorStack[bounces*3 + 0] = color.x;
                colorStack[bounces*3 + 1] = color.y;
                colorStack[bounces*3 + 2] = color.z;
            }

            break;
        }

        // Add color and emittance to proper stacks
        colorStack[bounces*3 + 0] = color.x;
        colorStack[bounces*3 + 1] = color.y;
        colorStack[bounces*3 + 2] = color.z;

        emittanceStack[bounces*3 + 0] = emittance.x;
        emittanceStack[bounces*3 + 1] = emittance.y;
        emittanceStack[bounces*3 + 2] = emittance.z;

        if (*preview) {
            // No need for ray bounce for preview
            break;
        } else if (nextFloat(random) <= color.w) {
            // Diffuse reflection
            diffuseReflect(&direction, &normal, random);
            typeStack[bounces] = 0;
        } else {
            // Transmission
            colorStack[bounces*3 + 0] = color.x * color.w + (1 - color.w);
            colorStack[bounces*3 + 1] = color.y * color.w + (1 - color.w);
            colorStack[bounces*3 + 2] = color.z * color.w + (1 - color.w);
            typeStack[bounces] = 1;
        }
        exitBlock(&origin, &direction, &temp, &distance);
    }

    if (*preview) {
        // preview shading = first intersect color * sun&ambient shading
        float shading = dot(normal, (float3) (0.25, 0.866, 0.433));
        if (shading < 0.3) shading = 0.3;

        colorStack[0] *= shading;
        colorStack[1] *= shading;
        colorStack[2] *= shading;
    } else {
        // rendering shading = accumulate over all bounces
        // TODO: implement specular shading
        for (int i = maxbounces - 1; i >= 0; i--) {
            switch (typeStack[i]) {
                case 0:
                    // Diffuse reflection
                    colorStack[i*3 + 0] *= colorStack[i*3 + 3] + emittanceStack[i*3 + 3];
                    colorStack[i*3 + 1] *= colorStack[i*3 + 4] + emittanceStack[i*3 + 4];
                    colorStack[i*3 + 2] *= colorStack[i*3 + 5] + emittanceStack[i*3 + 5];
                    break;
                case 1:
                    // Transmission
                    colorStack[i*3 + 0] *= colorStack[i*3 + 3];
                    colorStack[i*3 + 1] *= colorStack[i*3 + 4];
                    colorStack[i*3 + 2] *= colorStack[i*3 + 5];
                    break;
            }
        }
    }

    res[gid*3 + 0] = colorStack[0] * (emittanceStack[0] + 1);
    res[gid*3 + 1] = colorStack[1] * (emittanceStack[1] + 1);
    res[gid*3 + 2] = colorStack[2] * (emittanceStack[2] + 1);
}

// Xorshift random number generator based on the `xorshift32` presented in
// https://en.wikipedia.org/w/index.php?title=Xorshift&oldid=1007951001
void xorshift(unsigned int *state) {
    *state ^= *state << 13;
    *state ^= *state >> 17;
    *state ^= *state << 5;
    *state *= 0x5DEECE66D;
}

// Calculate the next float based on the formula on
// https://docs.oracle.com/javase/8/docs/api/java/util/Random.html#nextFloat--
float nextFloat(unsigned int *state) {
    xorshift(state);

    return (*state >> 8) / ((float) (1 << 24));
}

int entityIntersect(float3 *origin, float3 *direction, float3 *normal, float4 *color, float3 *emittance, float *distance, image2d_t entityData, image2d_t entityTrigs, image2d_t entityTextures) {
    int hit = 0;

    float tBest = *distance;
    int toVisit = 0;
    int currentNode = 0;
    int nodesToVisit[64];

    while (true) {
        // Each node is structured in:
        // <Sibling / Trig index>, <num primitives>, <6 * bounds>
        // Bounds array can be accessed with (node + 2)
        float node[8];
        areadf(entityData, currentNode, 8, node);

        if (aabbIntersectClose(origin, direction, &tBest, node+2)) {
            if (node[0] <= 0) {
                // Is leaf
                int primIndex = -node[0];
                int numPrim = node[1];

                for (int i = 0; i < numPrim; i++) {
                    int index = primIndex + i * 30;
                    switch ((int) indexf(entityTrigs, index)) {
                        case 0:
                            if (texturedTriangleIntersect(origin, direction, normal, color, emittance, distance, index, entityTrigs, entityTextures))
                                hit = 1;
                            break;
                    }
                }

                if (toVisit == 0) break;
                currentNode = nodesToVisit[--toVisit];
            } else {
                nodesToVisit[toVisit++] = node[0];
                currentNode = currentNode+8;
            }
        } else {
            if (toVisit == 0) break;
            currentNode = nodesToVisit[--toVisit];
        }
    }

    return hit;
}

// Generate a diffuse reflection ray. Based on chunky code
void diffuseReflect(float3 *direction, float3 *normal, unsigned int *state) {
    float x1 = nextFloat(state);
    float x2 = nextFloat(state);
    float r = sqrt(x1);
    float theta = 2 * M_PI * x2;

    float tx = r * cos(theta);
    float ty = r * sin(theta);
    float tz = sqrt(1 - x1);

    // transform from tangent space to world space
    float xx, xy, xz;
    float ux, uy, uz;
    float vx, vy, vz;

    if (fabs((*normal).x) > .1) {
      xx = 0;
      xy = 1;
      xz = 0;
    } else {
      xx = 1;
      xy = 0;
      xz = 0;
    }

    ux = xy * (*normal).z - xz * (*normal).y;
    uy = xz * (*normal).x - xx * (*normal).z;
    uz = xx * (*normal).y - xy * (*normal).x;

    r = rsqrt(ux * ux + uy * uy + uz * uz);

    ux *= r;
    uy *= r;
    uz *= r;

    vx = uy * (*normal).z - uz * (*normal).y;
    vy = uz * (*normal).x - ux * (*normal).z;
    vz = ux * (*normal).y - uy * (*normal).x;

    (*direction).x = ux * tx + vx * ty + (*normal).x * tz;
    (*direction).y = uy * tx + vy * ty + (*normal).y * tz;
    (*direction).z = uz * tx + vz * ty + (*normal).z * tz;
}

// Calculate the texture value of a ray
void getTextureRay(float3 *origin, float3 *normal, float4 *color, float3 *emittance, int block, image2d_t textures, image1d_t blockData, image2d_t grassTextures, image2d_t foliageTextures, int depth) {
    int bounds = 1 << depth;

    // Block data
    int4 blockD = read_imagei(blockData, indexSampler, block);

    // Calculate u,v value based on chunky code
    float u, v;
    float3 b = floor(*origin + (OFFSET * (*normal)));
    if ((*normal).y != 0) {
      u = (*origin).x - b.x;
      v = (*origin).z - b.z;
    } else if ((*normal).x != 0) {
      u = (*origin).z - b.z;
      v = (*origin).y - b.y;
    } else {
      u = (*origin).x - b.x;
      v = (*origin).y - b.y;
    }
    if ((*normal).x > 0 || (*normal).z < 0) {
      u = 1 - u;
    }
    if ((*normal).y > 0) {
      v = 1 - v;
    }

    u = u * 16 - EPS;
    v = (1 - v) * 16 - EPS;

    // Texture lookup index
    int index = blockD.x;
    index += 16 * (int) v + (int) u;

    // Lookup texture value
    unsigned int argb = indexu(textures, index);

    // Separate ARGB value
    (*color).x = (0xFF & (argb >> 16)) / 256.0;
    (*color).y = (0xFF & (argb >> 8 )) / 256.0;
    (*color).z = (0xFF & (argb >> 0 )) / 256.0;
    (*color).w = (0xFF & (argb >> 24)) / 256.0;

    // Calculate tint
    if (blockD.w != 0) {
        uint4 tintLookup;
        if (blockD.w == 1) {
            tintLookup = read_imageui(grassTextures, indexSampler, (int2)((b.x+bounds)/4, b.z+bounds));
        } else {
            tintLookup = read_imageui(foliageTextures, indexSampler, (int2)((b.x+bounds)/4, b.z+bounds));
        }
        unsigned int tintColor = tintLookup.x;

        switch ((int)(b.x + bounds) % 4) {
            case 0:
                tintColor = tintLookup.x;
            case 1:
                tintColor = tintLookup.y;
            case 2:
                tintColor = tintLookup.z;
            default:
                tintColor = tintLookup.w;
        }

        // Separate argb and add to color
        (*color).x *= (0xFF & (tintColor >> 16)) / 256.0;
        (*color).y *= (0xFF & (tintColor >> 8)) / 256.0;
        (*color).z *= (0xFF & (tintColor >> 0)) / 256.0;
    }

    // Calculate emittance
    (*emittance).x = (*color).x * (*color).x * (blockD.y / 256.0);
    (*emittance).y = (*color).y * (*color).y * (blockD.y / 256.0);
    (*emittance).z = (*color).z * (*color).z * (blockD.y / 256.0);
}

// Get the value of a location in the octree
int octreeGet(float3 *origin, image2d_t octreeData, int depth) {
    int nodeIndex = 0;
    int level = depth;

    int x = (*origin).x;
    int y = (*origin).y;
    int z = (*origin).z;

    int data = indexi(octreeData, nodeIndex);
    while (data > 0) {
        level -= 1;

        int lx = 1 & (x >> level);
        int ly = 1 & (y >> level);
        int lz = 1 & (z >> level);

        nodeIndex = data + ((lx << 2) | (ly << 1) | lz);
        data = indexi(octreeData, nodeIndex);
    }

    return -data;
}

// Check intersect with octree
// TODO: check BVH tree and custom block models
int octreeIntersect(float3 *origin, image2d_t octreeData, int depth, __global const int *transparent, int transparentLength) {
    int block = octreeGet(origin, octreeData, depth);

    for (int i = 0; i < transparentLength; i++)
        if (block == transparent[i])
            return 0;
    return 1;
}

// Check if we are inbounds
int octreeInbounds(float3 *origin, int depth) {
    int x = (*origin).x;
    int y = (*origin).y;
    int z = (*origin).z;

    int lx = x >> depth;
    int ly = y >> depth;
    int lz = z >> depth;

    return lx == 0 && ly == 0 && lz == 0;
}

// Exit the current block. Based on chunky code.
void exitBlock(float3 *origin, float3 *direction, float3 *normal, float *distance) {
    float tNext = 10000000;
    float3 b = floor(*origin);

    float t = (b.x - (*origin).x) / (*direction).x;
    if (t > EPS) {
        tNext = t;
        (*normal).x = 1;
        (*normal).y = (*normal).z = 0;
    } else {
        t = ((b.x + 1) - (*origin).x) / (*direction).x;
        if (t < tNext && t > EPS) {
            tNext = t;
            (*normal).x = -1;
            (*normal).y = (*normal).z = 0;
        }
    }

    t = (b.y - (*origin).y) / (*direction).y;
    if (t < tNext && t > EPS) {
        tNext = t;
        (*normal).y = 1;
        (*normal).x = (*normal).z = 0;
    }
    else {
        t = ((b.y + 1) - (*origin).y) / (*direction).y;
        if (t < tNext && t > EPS) {
            tNext = t;
            (*normal).y = -1;
            (*normal).x = (*normal).z = 0;
        }
    }

    t = (b.z - (*origin).z) / (*direction).z;
    if (t < tNext && t > EPS) {
        tNext = t;
        (*normal).z = 1;
        (*normal).x = (*normal).y = 0;
    } else {
        t = ((b.z + 1) - (*origin).z) / (*direction).z;
        if (t < tNext && t > EPS) {
            tNext = t;
            (*normal).z = -1;
            (*normal).x = (*normal).y = 0;
        }
    }

    tNext += OFFSET;
    *origin += tNext * (*direction);
    *distance += tNext;
}

void calcSkyRay(float3 *direction, float4 *color, float3 *emittance, image2d_t skyTexture, float3 sunPos, float sunIntensity, image2d_t textures, int sunIndex) {
    // Draw sun texture
    sunIntersect(direction, color, emittance, sunPos, textures, sunIndex);

    float theta = atan2((*direction).z, (*direction).x);
    theta /= M_PI * 2;
    theta = fmod(fmod(theta, 1) + 1, 1);
    float phi = (asin((*direction).y) + M_PI_2) * M_1_PI_F;

    float4 skyColor = read_imagef(skyTexture, skySampler, (float2)(theta, phi));

    *color += skyColor;
}

void sunIntersect(float3 *direction, float4 *color, float3 *emittance, float3 sunPos, image2d_t textures, int sunIndex) {
    float3 su = (float3) (0, 0, 0);
    float3 sv;

    if (fabs(sunPos.x) > 0.1)
        su.y = 1;
    else
        su.x = 1;

    sv = cross(sunPos, su);
    sv = normalize(sv);
    su = cross(sv, sunPos);

    float radius = 0.03;
    float width = radius * 4;
    float width2 = width * 2;
    float a;
    a = M_PI_2_F - acos(dot(*direction, su)) + width;
    if (a >= 0 && a < width2) {
        float b = M_PI_2_F - acos(dot(*direction, sv)) + width;
        if (b >= 0 && b < width2) {
            int index = sunIndex;
            index += (int)((a/width2) * 32 - EPS) + (int)((b/width2) * 32 - EPS) * 32;
            unsigned int argb = indexu(textures, index);

            // Separate ARGB value
            (*color).x = (0xFF & (argb >> 16)) / 256.0;
            (*color).y = (0xFF & (argb >> 8 )) / 256.0;
            (*color).z = (0xFF & (argb >> 0 )) / 256.0;
        }
    }
}

int aabbIntersect(float3 *origin, float3 *direction, float bounds[6]) {
    if (aabbInside(origin, bounds)) return 1;

    float3 r = 1 / *direction;

    float tx1 = (bounds[0] - (*origin).x) * r.x;
    float tx2 = (bounds[1] - (*origin).x) * r.x;

    float ty1 = (bounds[2] - (*origin).y) * r.y;
    float ty2 = (bounds[3] - (*origin).y) * r.y;

    float tz1 = (bounds[4] - (*origin).z) * r.z;
    float tz2 = (bounds[5] - (*origin).z) * r.z;

    float tmin = fmax(fmax(fmin(tx1, tx2), fmin(ty1, ty2)), fmin(tz1, tz2));
    float tmax = fmin(fmin(fmax(tx1, tx2), fmax(ty1, ty2)), fmax(tz1, tz2));

    return tmin <= tmax+OFFSET && tmin >= 0;
}

int aabbIntersectClose(float3 *origin, float3 *direction, float *distance, float bounds[6]) {
    if (aabbInside(origin, bounds)) return 1;

    float3 r = 1 / *direction;

    float tx1 = (bounds[0] - (*origin).x) * r.x;
    float tx2 = (bounds[1] - (*origin).x) * r.x;

    float ty1 = (bounds[2] - (*origin).y) * r.y;
    float ty2 = (bounds[3] - (*origin).y) * r.y;

    float tz1 = (bounds[4] - (*origin).z) * r.z;
    float tz2 = (bounds[5] - (*origin).z) * r.z;

    float tmin = fmax(fmax(fmin(tx1, tx2), fmin(ty1, ty2)), fmin(tz1, tz2));
    float tmax = fmin(fmin(fmax(tx1, tx2), fmax(ty1, ty2)), fmax(tz1, tz2));

    return tmin <= tmax+OFFSET && tmin >= 0 && tmin <= *distance;
}

int aabbInside(float3 *origin, float bounds[6]) {
    return (*origin).x >= bounds[0] && (*origin).x <= bounds[1] &&
           (*origin).y >= bounds[2] && (*origin).y <= bounds[3] &&
           (*origin).z >= bounds[4] && (*origin).z <= bounds[5];
}

int texturedTriangleIntersect(float3 *origin, float3 *direction, float3 *normal, float4 *color, float3 *emittance, float *distance, int index, image2d_t entityTrigs, image2d_t entityTextures) {
    // Check aabb
    float aabb[6];
    areadf(entityTrigs, index+1, 6, aabb);

    if (!aabbIntersectClose(origin, direction, distance, aabb)) return 0;   // Does not intersect

    float3 e1, e2, o, n;
    float2 t1, t2, t3;
    int doubleSided;

    float trig[19];
    areadf(entityTrigs, index+7, 19, trig);

    e1 = (float3)(trig[0], trig[1], trig[2]);

    e2 = (float3)(trig[3], trig[4], trig[5]);

    o = (float3)(trig[6], trig[7], trig[8]);

    n = (float3)(trig[9], trig[10], trig[11]);

    t1 = (float2)(trig[12], trig[13]);

    t2 = (float2)(trig[14], trig[15]);

    t3 = (float2)(trig[16], trig[17]);

    doubleSided = trig[18];

    float3 pvec, qvec, tvec;

    pvec = cross(*direction, e2);
    float det = dot(e1, pvec);
    if (doubleSided) {
        if (det > -EPS && det < EPS) return 0;
    } else if (det > -EPS) {
        return 0;
    }
    float recip = 1 / det;

    tvec = *origin - o;

    float u = dot(tvec, pvec) * recip;

    if (u < 0 || u > 1) return 0;

    qvec = cross(tvec, e1);

    float v = dot(*direction, qvec) * recip;

    if (v < 0 || (u+v) > 1) return 0;

    float t = dot(e2, qvec) * recip;

    if (t > EPS && t < *distance) {
        float w = 1 - u - v;
        float2 uv = (float2) (t1.x * u + t2.x * v + t3.x * w,
                              t1.y * u + t2.y * v + t3.y * w);

        float tex[4];
        areadf(entityTrigs, index+26, 4, tex);

        float width = tex[0];
        float height = tex[1];

        int x = uv.x * width - EPS;
        int y = (1 - uv.y) * height - EPS;

        unsigned int argb = indexu(entityTextures, width*y + x + tex[3]);
        float emit = tex[2];

        if ((0xFF & (argb >> 24)) > 0) {
            *distance = t;

            (*color).x = (0xFF & (argb >> 16)) / 256.0;
            (*color).y = (0xFF & (argb >> 8 )) / 256.0;
            (*color).z = (0xFF & (argb >> 0 )) / 256.0;
            (*color).w = (0xFF & (argb >> 24)) / 256.0;

            *emittance = (*color).xyz * (*color).xyz * emit;
            *normal = n;

            return 1;
        }
    }

    return 0;
}

float indexf(image2d_t img, int index) {
    float4 roi = read_imagef(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
    switch (index % 4) {
        case 0: return roi.x;
        case 1: return roi.y;
        case 2: return roi.z;
        default: return roi.w;
    }
}

int indexi(image2d_t img, int index) {
    int4 roi = read_imagei(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
    switch (index % 4) {
        case 0: return roi.x;
        case 1: return roi.y;
        case 2: return roi.z;
        default: return roi.w;
    }
}

unsigned int indexu(image2d_t img, int index) {
    uint4 roi = read_imageui(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
    switch (index % 4) {
        case 0: return roi.x;
        case 1: return roi.y;
        case 2: return roi.z;
        default: return roi.w;
    }
}

void areadf(image2d_t img, int index, int length, float output[]) {
    float4 roi = read_imagef(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
    for (int i = 0; i < length; i++) {
        if ((index + i) % 4 == 0 && i != 0) {
            index += 4;
            roi = read_imagef(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
        }

        switch ((index + i) % 4) {
            case 0: output[i] = roi.x; break;
            case 1: output[i] = roi.y; break;
            case 2: output[i] = roi.z; break;
            default: output[i] = roi.w; break;
        }
    }
}

void areadi(image2d_t img, int index, int length, int output[]) {
    int4 roi = read_imagei(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
    for (int i = 0; i < length; i++) {
        if ((index + i) % 4 == 0 && i != 0) {
            index += 4;
            roi = read_imagei(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
        }

        switch ((index + i) % 4) {
            case 0: output[i] = roi.x; break;
            case 1: output[i] = roi.y; break;
            case 2: output[i] = roi.z; break;
            default: output[i] = roi.w; break;
        }
    }
}

void areadu(image2d_t img, int index, int length, unsigned int output[]) {
    uint4 roi = read_imageui(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
    for (int i = 0; i < length; i++) {
        if ((index + i) % 4 == 0 && i != 0) {
            index += 4;
            roi = read_imageui(img, indexSampler, (int2) ((index / 4) % 8192, (index / 4) / 8192));
        }

        switch ((index + i) % 4) {
            case 0: output[i] = roi.x; break;
            case 1: output[i] = roi.y; break;
            case 2: output[i] = roi.z; break;
            default: output[i] = roi.w; break;
        }
    }
}
