//
//  Created by sarsonj on 12/5/11.
//
// To change the template use AppCode | Preferences | File Templates.
//


#import "LowpassFilter.h"

#define DEFAULT_LOW_PASS_PARAM 0.1

@implementation LowpassFilter {
    float lowPassParam;
    float currentValue;
    float latestValue;
}

@synthesize currentValue;
@synthesize latestValue;


- (id)initWithParam:(float)param {
    self = [super init];
    if (self) {
        lowPassParam = param;
    }
    return self;

}

-(void)reset {
    currentValue = 0;
}


-(float)addNextValueToFilter:(float)value {
    latestValue = value;
    float newValue = DEFAULT_LOW_PASS_PARAM * value + (1 - DEFAULT_LOW_PASS_PARAM) * currentValue;
    currentValue = newValue;
    return currentValue;
}

@end