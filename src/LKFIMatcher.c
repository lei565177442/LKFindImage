//
//  LKFIMatcher.c
//  纯 C 实现的灰度模板匹配：NCC + 积分图 + 4/8 倍降采样金字塔 + 全分辨率精修 + NMS
//

#include "LKFIMatcher.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct {
    int   x;
    int   y;
    double score;
} RawHit;

typedef struct {
    const uint8_t *p;
    int    w;
    int    h;
    int    n;
    double mean;
    double var;
} Tpl;

/* ---------------- 基础工具 ---------------- */

static uint8_t *lkfi_ds(const uint8_t *src, int w, int h, int d, int *ow, int *oh)
{
    int nw = w / d;
    int nh = h / d;
    if (nw <= 0 || nh <= 0) return NULL;

    uint8_t *out = (uint8_t *)malloc((size_t)nw * (size_t)nh);
    if (!out) return NULL;

    int cnt = d * d;
    for (int y = 0; y < nh; y++) {
        for (int x = 0; x < nw; x++) {
            int acc = 0;
            for (int yy = 0; yy < d; yy++) {
                const uint8_t *row = src + (size_t)(y * d + yy) * (size_t)w + (size_t)x * (size_t)d;
                for (int xx = 0; xx < d; xx++) acc += row[xx];
            }
            out[(size_t)y * (size_t)nw + (size_t)x] = (uint8_t)(acc / cnt);
        }
    }
    *ow = nw;
    *oh = nh;
    return out;
}

static void lkfi_integral(const uint8_t *s, int w, int h, double *si, double *sq)
{
    int W = w + 1;
    for (int x = 0; x <= w; x++) { si[x] = 0.0; sq[x] = 0.0; }

    for (int y = 0; y < h; y++) {
        double rs = 0.0, rq = 0.0;
        const uint8_t *row = s + (size_t)y * (size_t)w;
        double *dsi = si + (size_t)(y + 1) * (size_t)W;
        double *dsq = sq + (size_t)(y + 1) * (size_t)W;
        const double *psi = si + (size_t)y * (size_t)W;
        const double *psq = sq + (size_t)y * (size_t)W;
        dsi[0] = 0.0;
        dsq[0] = 0.0;
        for (int x = 0; x < w; x++) {
            double v = (double)row[x];
            rs += v;
            rq += v * v;
            dsi[x + 1] = psi[x + 1] + rs;
            dsq[x + 1] = psq[x + 1] + rq;
        }
    }
}

static inline double lkfi_rsum(const double *ii, int w, int x0, int y0, int x1, int y1)
{
    int W = w + 1;
    return ii[(size_t)y1 * (size_t)W + (size_t)x1]
         - ii[(size_t)y0 * (size_t)W + (size_t)x1]
         - ii[(size_t)y1 * (size_t)W + (size_t)x0]
         + ii[(size_t)y0 * (size_t)W + (size_t)x0];
}

static int lkfi_tpl_init(Tpl *t, const uint8_t *p, int w, int h)
{
    int n = w * h;
    if (n <= 0) return 0;

    double s = 0.0, q = 0.0;
    for (int i = 0; i < n; i++) {
        double v = (double)p[i];
        s += v;
        q += v * v;
    }
    double mean = s / (double)n;
    double var = q - (double)n * mean * mean;
    if (var < 1.0) return 0;            /* 模板接近纯色，无法稳定匹配 */

    t->p = p;
    t->w = w;
    t->h = h;
    t->n = n;
    t->mean = mean;
    t->var = var;
    return 1;
}

/* ---------------- 全图扫描 ---------------- */

static int lkfi_rawscan(const uint8_t *I, int iw, int ih, const Tpl *t, double thr,
                        RawHit **outArr, int *outCount)
{
    *outArr = NULL;
    *outCount = 0;

    int tw = t->w, th = t->h, n = t->n;
    if (iw < tw || ih < th) return 0;

    int W = iw + 1;
    double *si = (double *)calloc((size_t)W * (size_t)(ih + 1), sizeof(double));
    double *sq = (double *)calloc((size_t)W * (size_t)(ih + 1), sizeof(double));
    if (!si || !sq) { free(si); free(sq); return 0; }

    lkfi_integral(I, iw, ih, si, sq);

    int cap = 1024;
    int cnt = 0;
    RawHit *arr = (RawHit *)malloc(sizeof(RawHit) * (size_t)cap);
    if (!arr) { free(si); free(sq); return 0; }

    double sqrtVarT = sqrt(t->var);
    double nD = (double)n;
    int maxX = iw - tw;
    int maxY = ih - th;

    for (int y = 0; y <= maxY; y++) {
        for (int x = 0; x <= maxX; x++) {
            double sI = lkfi_rsum(si, iw, x, y, x + tw, y + th);
            double qI = lkfi_rsum(sq, iw, x, y, x + tw, y + th);
            double meanI = sI / nD;
            double varI = qI - nD * meanI * meanI;
            if (varI < 1.0) continue;

            int64_t cross = 0;
            for (int ty = 0; ty < th; ty++) {
                const uint8_t *ri = I + (size_t)(y + ty) * (size_t)iw + (size_t)x;
                const uint8_t *rt = t->p + (size_t)ty * (size_t)tw;
                for (int tx = 0; tx < tw; tx++) {
                    cross += (int64_t)ri[tx] * (int64_t)rt[tx];
                }
            }

            double score = ((double)cross - nD * meanI * t->mean) / (sqrt(varI) * sqrtVarT);
            if (score < thr) continue;

            if (cnt == cap) {
                if (cap >= 32768) continue;
                cap *= 2;
                RawHit *na = (RawHit *)realloc(arr, sizeof(RawHit) * (size_t)cap);
                if (!na) break;
                arr = na;
            }
            arr[cnt].x = x;
            arr[cnt].y = y;
            arr[cnt].score = score;
            cnt++;
        }
    }

    free(si);
    free(sq);
    *outArr = arr;
    *outCount = cnt;
    return cnt;
}

/* ---------------- 单点精确计算 ---------------- */

static double lkfi_ncc_at(const uint8_t *I, int iw, int ih, const Tpl *t, int x, int y)
{
    if (x < 0 || y < 0) return -2.0;
    if (x + t->w > iw || y + t->h > ih) return -2.0;

    int tw = t->w, th = t->h, n = t->n;
    double sI = 0.0, qI = 0.0;
    int64_t cross = 0;

    for (int ty = 0; ty < th; ty++) {
        const uint8_t *ri = I + (size_t)(y + ty) * (size_t)iw + (size_t)x;
        const uint8_t *rt = t->p + (size_t)ty * (size_t)tw;
        double rs = 0.0;
        for (int tx = 0; tx < tw; tx++) {
            double v = (double)ri[tx];
            rs += v;
            qI += v * v;
            cross += (int64_t)ri[tx] * (int64_t)rt[tx];
        }
        sI += rs;
    }

    double nD = (double)n;
    double meanI = sI / nD;
    double varI = qI - nD * meanI * meanI;
    if (varI < 1.0) return -2.0;

    return ((double)cross - nD * meanI * t->mean) / (sqrt(varI) * sqrt(t->var));
}

/* ---------------- 排序 ---------------- */

static int lkfi_cmp_desc(const void *a, const void *b)
{
    double sa = ((const RawHit *)a)->score;
    double sb = ((const RawHit *)b)->score;
    if (sa < sb) return 1;
    if (sa > sb) return -1;
    return 0;
}

/* ---------------- 对外入口 ---------------- */

int lkfi_match(const uint8_t *img, int iw, int ih,
               const uint8_t *tpl, int tw, int th,
               float threshold, int maxHits, float minDist,
               LKFIHit *out, int cap)
{
    if (!img || !tpl || !out || cap <= 0) return 0;
    if (iw <= 0 || ih <= 0 || tw < 4 || th < 4) return 0;
    if (tw > iw || th > ih) return 0;
    if (maxHits <= 0) maxHits = cap;
    if (maxHits > cap) maxHits = cap;

    Tpl t0;
    if (!lkfi_tpl_init(&t0, tpl, tw, th)) return 0;

    double thr = (double)threshold;
    if (thr < 0.05) thr = 0.05;
    if (thr > 1.0) thr = 1.0;

    long long area = (long long)iw * (long long)ih;
    int d = 1;
    if (tw >= 32 && th >= 32 && area > 200000LL) d = 4;
    if (tw >= 64 && th >= 64 && area > 1600000LL) d = 8;

    RawHit *cands = NULL;
    int ncand = 0;
    int pyramidOK = 0;

    if (d > 1) {
        int nw = 0, nh = 0, ntw = 0, nth = 0;
        uint8_t *S = lkfi_ds(img, iw, ih, d, &nw, &nh);
        uint8_t *D = lkfi_ds(tpl, tw, th, d, &ntw, &nth);

        if (S && D && ntw >= 4 && nth >= 4 && nw >= ntw && nh >= nth) {
            Tpl td;
            if (lkfi_tpl_init(&td, D, ntw, nth)) {
                pyramidOK = 1;

                RawHit *coarse = NULL;
                int ncoarse = 0;
                double thr2 = thr - 0.30;
                if (thr2 < 0.30) thr2 = 0.30;

                lkfi_rawscan(S, nw, nh, &td, thr2, &coarse, &ncoarse);

                if (ncoarse > 1) qsort(coarse, (size_t)ncoarse, sizeof(RawHit), lkfi_cmp_desc);
                if (ncoarse > 48) ncoarse = 48;

                if (ncoarse > 0) {
                    cands = (RawHit *)malloc(sizeof(RawHit) * (size_t)ncoarse);
                    if (cands) {
                        for (int i = 0; i < ncoarse; i++) {
                            int ox = coarse[i].x * d;
                            int oy = coarse[i].y * d;
                            double best = -2.0;
                            int bx = ox, by = oy;

                            for (int dy = -d; dy <= d; dy++) {
                                for (int dx = -d; dx <= d; dx++) {
                                    double s = lkfi_ncc_at(img, iw, ih, &t0, ox + dx, oy + dy);
                                    if (s > best) { best = s; bx = ox + dx; by = oy + dy; }
                                }
                            }
                            if (best >= thr) {
                                cands[ncand].x = bx;
                                cands[ncand].y = by;
                                cands[ncand].score = best;
                                ncand++;
                            }
                        }
                    }
                }
                free(coarse);
            }
        }
        free(S);
        free(D);
    }

    if (!pyramidOK) {
        lkfi_rawscan(img, iw, ih, &t0, thr, &cands, &ncand);
    }

    if (ncand <= 0) {
        free(cands);
        return 0;
    }

    if (ncand > 1) qsort(cands, (size_t)ncand, sizeof(RawHit), lkfi_cmp_desc);

    float md = minDist;
    if (md <= 0.0f) md = (float)((tw < th ? tw : th) / 2);
    if (md < 4.0f) md = 4.0f;
    float md2 = md * md;

    int nout = 0;
    for (int i = 0; i < ncand && nout < maxHits; i++) {
        int keep = 1;
        for (int j = 0; j < nout; j++) {
            float dx = (float)(cands[i].x - out[j].x);
            float dy = (float)(cands[i].y - out[j].y);
            if (dx * dx + dy * dy < md2) { keep = 0; break; }
        }
        if (!keep) continue;

        out[nout].x = cands[i].x;
        out[nout].y = cands[i].y;
        out[nout].w = tw;
        out[nout].h = th;
        out[nout].score = (float)cands[i].score;
        nout++;
    }

    free(cands);
    return nout;
}
