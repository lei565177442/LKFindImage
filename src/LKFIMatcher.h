//
//  LKFIMatcher.h
//  灰度模板匹配（NCC 归一化互相关），金字塔加速，多命中 + NMS
//

#ifndef LKFIMatcher_h
#define LKFIMatcher_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int   x;        // 命中左上角 X（像素，相对搜索区域）
    int   y;        // 命中左上角 Y（像素，相对搜索区域）
    int   w;        // 模板宽（像素）
    int   h;        // 模板高（像素）
    float score;    // 相似度 0.0 ~ 1.0
} LKFIHit;

/*
 * lkfi_match
 *   img/tpl 均为 8bit 灰度数据（每行紧密排列，stride == width）
 *   threshold 为相似度下限（0~1）
 *   maxHits   最多返回多少个命中点
 *   minDist   非极大值抑制的最近距离（像素），避免同一个目标返回一堆重叠框
 *   返回实际命中数量，结果写进 out[0..n-1]，按分数从高到低排列
 */
int lkfi_match(const uint8_t *img, int iw, int ih,
               const uint8_t *tpl, int tw, int th,
               float threshold, int maxHits, float minDist,
               LKFIHit *out, int cap);

#ifdef __cplusplus
}
#endif

#endif /* LKFIMatcher_h */
