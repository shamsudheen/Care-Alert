//
//  Constants.m
//  Care Alert
//
//  Created by Sham on 27/10/17.
//  Copyright © 2017 M-Phi Innovators LLC. All rights reserved.
//

#import "Constants.h"

@implementation Constants

NSString const *kAPIBaseURL          = @"http://52.27.208.155:3000/";
NSString const *kAPISendNotification = @"integrations/sendNotification";

NSString const *kHTTPMethodPost = @"POST";
NSString const *kHTTPMethodGet  = @"GET";

NSString const *kProgressTitle = @"Notifying..";

NSString const *kAlertSuccessMsg = @"Notified all!";
NSString const *kAlertErrorMsg   = @"Server error!";

@end
