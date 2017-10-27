//
//  ResponseTracker.h
//  Care Alert
//
//  Created by Sham on 28/10/17.
//  Copyright © 2017 M-Phi Innovators LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ResponseTracker : NSObject

@property (nonatomic, assign) BOOL isHeartBeatReceived;
@property (nonatomic, assign) BOOL isBloodpressureReceived;
@property (nonatomic, assign) BOOL isLocationReceived;
@property (nonatomic, assign) BOOL isActivityReceived;
@property (nonatomic, assign) BOOL isServerNotified;

@end
