//
//  PngWriter.m
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 2/15/22.
//  Copyright © 2022 Stray Robots. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PngEncoder.h"
#import "lodepng.h"
#include <cmath>

@implementation PngEncoder {
    std::vector<unsigned char> png;
    std::vector<unsigned char> inputImage;
    int height;
    int width;
}
- (instancetype) initWithDepth:(float*) content width:(int) w height:(int) h {
    self = [super init];
    width = w;
    height = h;
    inputImage.resize(width * height * 2);
    unsigned char* outData = inputImage.data();
    for (int y=0; y < height; y++) {
        for (int x=0; x < width; x++) {
            float value = content[y * width + x];
            uint16_t converted = uint16_t(std::round(value * 1000.0f));
            unsigned int index = (y * width + x) * 2;
            outData[index] = converted >> 8;
            outData[index+1] = converted & 0xFF;
        }
    }
    return self;
}

- (NSData*) fileContents {
    lodepng::State state;
    state.info_raw.colortype = LCT_GREY;
    state.info_raw.bitdepth = 16;
    state.info_png.color.colortype = LCT_GREY;
    state.info_png.color.bitdepth = 16;
    state.encoder.auto_convert = 0;
    state.encoder.filter_strategy = LFS_ZERO;
    state.encoder.zlibsettings.lazymatching = 0;
    state.encoder.zlibsettings.windowsize = 1024;
    png.clear();
    if (lodepng::encode(png, inputImage, width, height, state) != 0) {
        return nil;
    }
    NSData* outData = [[NSData alloc] initWithBytes:(void*)png.data() length:png.size()];
    return outData;
}


@end
