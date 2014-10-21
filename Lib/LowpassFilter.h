//
//  Created by sarsonj on 12/5/11.
//
// To change the template use AppCode | Preferences | File Templates.
//


#import <Foundation/Foundation.h>


@interface LowpassFilter : NSObject {

}


@property(nonatomic, readonly) float currentValue;
@property(nonatomic, readonly) float latestValue;


- (id)initWithParam:(float)param;

- (void)reset;

- (float)addNextValueToFilter:(float)value;
@end