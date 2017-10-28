//
//  InterfaceController.m
//  Care Alert POC Watch App Extension
//
//  Created by Sham on 22/10/17.
//  Copyright © 2017 M-Phi Innovators LLC. All rights reserved.
//

#import "InterfaceController.h"
#import <HealthKit/HealthKit.h>
#import <CoreMotion/CoreMotion.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "Constants.h"
#import "ResponseTracker.h"

@interface InterfaceController () <HKWorkoutSessionDelegate, CLLocationManagerDelegate>

// outlets vars
@property (nonatomic, weak) IBOutlet WKInterfaceButton *btnAlert;
@property (nonatomic, weak) IBOutlet WKInterfaceLabel  *lblStatus;

//error vars
@property (nonatomic, strong) NSError  *activityError;

//to track each response of the user info request
@property (nonatomic, strong) ResponseTracker *responseTracker;

//user info vars
@property (nonatomic, strong) NSString *heartBeatRate;
@property (nonatomic, strong) NSString *bloodpressure;
@property (nonatomic, strong) NSString *movement;
@property (nonatomic, strong) NSString *location;

//health-kit vars
@property (nonatomic, strong)  HKHealthStore    *healthStore;
@property (nonatomic, strong)  HKWorkoutSession *workoutSession;
@property (nonatomic, strong)  HKAnchoredObjectQuery  *heartbeatQuery;
@property (nonatomic, strong)  HKCorrelationQuery     *bloodpressureQuery;
@property (nonatomic, assign)  BOOL                   isHealthMonitorAllowed;

//motion vars
@property (nonatomic, strong) CMMotionActivityManager *motionActivityManager;

//location vars
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLGeocoder        *geocoder;
@property (nonatomic, assign)  BOOL             isGeocodeLocationReversed;


@end

@implementation InterfaceController

- (void)awakeWithContext:(id)context {
    [super awakeWithContext:context];
    
    _geocoder = [[CLGeocoder alloc] init];
    
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    [self.locationManager requestWhenInUseAuthorization];
    
    _healthStore   = [[HKHealthStore alloc] init];
    
    HKQuantityType *type = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeartRate];
    HKQuantityType *type2 = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureSystolic];
    HKQuantityType *type3 = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureDiastolic];
    
    [_healthStore requestAuthorizationToShareTypes:nil readTypes:[NSSet setWithObjects:type, type2, type3, nil] completion:^(BOOL success, NSError * _Nullable error) {
        
        if (YES == success) {
            _isHealthMonitorAllowed = YES;
        }
    }];
    
    // check to see if the device can handle motion activity
    if ([CMMotionActivityManager isActivityAvailable]) {
        // if so, initialize the activity manager
        _motionActivityManager = [[CMMotionActivityManager alloc] init];
    }
}

- (void)willActivate {
    [super willActivate];
}

- (void)didDeactivate {
    [super didDeactivate];
}

- (IBAction)touchToAlert:(id)sender {
    
    [_btnAlert setEnabled:NO];
    
    [_lblStatus setText:(NSString *)kProgressTitle];
    
    [self startTracking];
}

- (void)updateStatus:(NSError *)error {
    
    NSString *message = (NSString *)kAlertSuccessMsg;
    if (error) {
        message = (NSString *)kAlertErrorMsg;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_lblStatus setText:(NSString *)message];
        [_btnAlert setEnabled:YES];
        [self stopAllTracking];
    });
}

- (void)startWorkout {
    
    if (YES == _isHealthMonitorAllowed) {
        // If we have already started the workout, then do nothing.
        if (self.workoutSession == nil) {
            self.workoutSession = [[HKWorkoutSession alloc] initWithActivityType:HKWorkoutActivityTypeCrossTraining locationType:HKWorkoutSessionLocationTypeIndoor];
            [self.workoutSession setDelegate:self];
            [_healthStore startWorkoutSession:self.workoutSession];
        }
    } else {
        
        _responseTracker.isHeartBeatReceived = YES;
        _responseTracker.isBloodpressureReceived = YES;
       
        [self notifyServerAPI];
    }
}

- (void)stopWorkout {
    
    [self stopHeartbeatQuery];
    
    [self stopBloodpressureQuery];
    
    if (self.workoutSession != nil) {
        [self.workoutSession setDelegate:nil];
        [_healthStore endWorkoutSession:self.workoutSession];
        self.workoutSession = nil;
    }
}

- (void)workoutSession:(HKWorkoutSession *)workoutSession didFailWithError:(NSError *)error{
    _activityError = error;
    _responseTracker.isBloodpressureReceived = YES;
    _responseTracker.isHeartBeatReceived = YES;
    
    [self notifyServerAPI];
}

- (void)workoutSession:(HKWorkoutSession *)workoutSession didChangeToState:(HKWorkoutSessionState)toState fromState:(HKWorkoutSessionState)fromState date:(NSDate *)date{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (toState) {
            case HKWorkoutSessionStateRunning:
                [self updateHeartbeat:date];
                [self updateBloodPressure:date];
                break;
            default:
                break;
        }
    });
}

- (void)updateHeartbeat:(NSDate *)startDate {
    
    __weak typeof(self) weakSelf = self;
    __weak typeof(ResponseTracker) *weakResponseTracker = _responseTracker;
    
    //first, create a predicate and set the endDate and option to nil/none 
    NSPredicate *Predicate = [HKQuery predicateForSamplesWithStartDate:startDate endDate:nil options:HKQueryOptionNone];
    
    //Then we create a sample type which is HKQuantityTypeIdentifierHeartRate
    HKSampleType *object = [HKSampleType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeartRate];
    
    //ok, now, create a HKAnchoredObjectQuery with all the mess that we just created.
    _heartbeatQuery = [[HKAnchoredObjectQuery alloc] initWithType:object predicate:Predicate anchor:0 limit:0 resultsHandler:^(HKAnchoredObjectQuery *query, NSArray<HKSample *> *sampleObjects, NSArray<HKDeletedObject *> *deletedObjects, HKQueryAnchor *newAnchor, NSError *error) {
        
        if (!error) {
            
            if (sampleObjects.count > 0) {
                HKQuantitySample *sample = (HKQuantitySample *)[sampleObjects objectAtIndex:0];
                HKQuantity *quantity = sample.quantity;
                
                _heartBeatRate = [NSString stringWithFormat:@"%f  bpm", [quantity doubleValueForUnit:[HKUnit unitFromString:@"count/min"]]];
                
                _activityError = error;
                
                _responseTracker.isHeartBeatReceived = YES;
                
                [weakSelf stopHeartbeatQuery];
                
                [weakSelf notifyServerAPI];
            }
        }else {
           
            _activityError = error;
            
            _responseTracker.isHeartBeatReceived = YES;
            
            [weakSelf stopHeartbeatQuery];
            
            [weakSelf notifyServerAPI];
        }
    }];
    
    //wait, it's not over yet, this is the update handler
    [_heartbeatQuery setUpdateHandler:^(HKAnchoredObjectQuery *query, NSArray<HKSample *> *SampleArray, NSArray<HKDeletedObject *> *deletedObjects, HKQueryAnchor *Anchor, NSError *error) {
        
        if (!error) {
            
            if (SampleArray.count > 0) {
                HKQuantitySample *sample = (HKQuantitySample *)[SampleArray objectAtIndex:0];
                HKQuantity *quantity = sample.quantity;
                
                _heartBeatRate = [NSString stringWithFormat:@"%f  bpm", [quantity doubleValueForUnit:[HKUnit unitFromString:@"count/min"]]];
                
                _activityError = error;
                
                weakResponseTracker.isHeartBeatReceived = YES;
                
                [weakSelf stopHeartbeatQuery];
                
                [weakSelf notifyServerAPI];
            }
            
        }else {
            
            _activityError = error;
            
            weakResponseTracker.isHeartBeatReceived = YES;
          
            [weakSelf stopHeartbeatQuery];
            
            [weakSelf notifyServerAPI];
        }
    }];
    
    //now excute query and wait for the result showing up in the log. Yeah!
    [_healthStore executeQuery:_heartbeatQuery];
}

- (void)updateBloodPressure:(NSDate *)startDate {
    
    HKQuantityType *systolicType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureSystolic];
    HKQuantityType *diastolicType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureDiastolic];
    HKCorrelationType *bloodPressureType =
    [HKCorrelationType correlationTypeForIdentifier:HKCorrelationTypeIdentifierBloodPressure];
    
    _bloodpressureQuery =
    [[HKCorrelationQuery alloc]
     initWithType:bloodPressureType predicate:nil
     samplePredicates:nil
     completion:^(HKCorrelationQuery *query, NSArray *correlations, NSError *error) {
         if (correlations == nil) {
              _activityError = error;
         }
         for (HKCorrelation *correlation in correlations) {
             HKQuantitySample *systolicSample = [[correlation objectsForType:systolicType] anyObject];
             HKQuantity *systolicQuantity = [systolicSample quantity];
             HKQuantitySample *diastolicSample = [[correlation objectsForType:diastolicType] anyObject];
             HKQuantity *diastolicQuantity = [diastolicSample quantity];
             double systolicd = [systolicQuantity doubleValueForUnit:[HKUnit millimeterOfMercuryUnit]];
             double diastolicd = [diastolicQuantity doubleValueForUnit:[HKUnit millimeterOfMercuryUnit]];
             
             NSString *bloodpressureSystolic  = [[NSString alloc] initWithFormat:@"Systolic-%f mmHg ",systolicd];
             NSString *bloodpressureDiastolic = [[NSString alloc] initWithFormat:@"Diastolic-%f mmHg",diastolicd];
             _bloodpressure = [[bloodpressureSystolic stringByAppendingString:bloodpressureSystolic] stringByAppendingString:bloodpressureDiastolic];
         }
        
         _responseTracker.isBloodpressureReceived = YES;
         
         [self notifyServerAPI];
     }];
    
    [self.healthStore executeQuery:_bloodpressureQuery];
}

- (void)stopHeartbeatQuery {
    
    if (_heartbeatQuery != nil) {
        [_healthStore stopQuery:_heartbeatQuery];
    }
    _heartbeatQuery = nil;
}

- (void)stopBloodpressureQuery {
    
    if (_bloodpressureQuery != nil) {
        [_healthStore stopQuery:_bloodpressureQuery];
    }
    _bloodpressureQuery = nil;
}

- (void)updateUserMovement {
    
    if (NO == [CMMotionActivityManager isActivityAvailable]) {
        _responseTracker.isActivityReceived = YES;
        
        [self notifyServerAPI];
    }
    
    [_motionActivityManager startActivityUpdatesToQueue:[[NSOperationQueue alloc] init]
                                            withHandler:
     ^(CMMotionActivity *activity) {
 
         if ([activity stationary]) {
             _movement = @"Stationary";
         } else if ([activity walking]) {
             _movement = @"Walking";
         }else if ([activity running]) {
             _movement = @"Running";
         }else if ([activity automotive]) {
             _movement = @"Automotive";
         }else if ([activity cycling]) {
             _movement = @"Cycling";
         } else {
             _movement = @"Stationary";
         }
         _responseTracker.isActivityReceived = YES;
         
         [self notifyServerAPI];
     }];
}

- (void)startTrackingCurrentLocation {
    
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status == kCLAuthorizationStatusAuthorizedAlways || status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        if (@available(watchOS 3.0, *)) {
            [self.locationManager startUpdatingLocation];
        } else {
            [self.locationManager requestLocation];
        }
    }
    else {
        
        _activityError = [NSError errorWithDomain:@"GPS" code:14 userInfo:[NSDictionary dictionaryWithObject:@"Unauthorized GPS Access.  Please open Topo Maps+ on your iPhone and tap on current location." forKey:NSLocalizedDescriptionKey]];
        _responseTracker.isLocationReceived = YES;
        
        [self notifyServerAPI];
    }
}

- (void)stopTrackingCurrentLocation {
    [self.locationManager stopUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    if (_isGeocodeLocationReversed == NO) {
        if (locations.count > 0) {
            _isGeocodeLocationReversed = YES;
            CLLocation *currentLocation = [locations objectAtIndex:0];
            [_geocoder reverseGeocodeLocation:currentLocation completionHandler:^(NSArray *placemarks, NSError *error) {
                if (!(error)) {
                    CLPlacemark *placemark = [placemarks objectAtIndex:0];
                    _location = [[placemark.addressDictionary valueForKey:@"FormattedAddressLines"] componentsJoinedByString:@", "];
                    _responseTracker.isLocationReceived = YES;
                }
                else {
                    _activityError = error;
                    _responseTracker.isLocationReceived = YES;
                }
                [self notifyServerAPI];
            }];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(nonnull NSError *)error {
    _activityError = error;
    _responseTracker.isLocationReceived = YES;
    
    [self notifyServerAPI];
}

- (void)startTracking {
    [self clearAllResponses];
    [self startWorkout];
    [self updateUserMovement];
    [self startTrackingCurrentLocation];
}

- (void)stopAllTracking {
    [self stopWorkout];
    [self stopTrackingCurrentLocation];
    [_motionActivityManager stopActivityUpdates];
    [self clearAllResponses];
}

- (void)clearAllResponses {
    
    _responseTracker = [[ResponseTracker alloc] init];
    
    _movement      = @"";
    _location      = @"";
    _heartBeatRate = @"";
    _bloodpressure = @"";
    
    _isGeocodeLocationReversed = NO;
}

- (void)notifyServerAPI {
    
    if (_responseTracker.isHeartBeatReceived &&
        _responseTracker.isBloodpressureReceived &&
        _responseTracker.isLocationReceived &&
        _responseTracker.isActivityReceived &&
        !_responseTracker.isServerNotified) {
        
        _responseTracker.isServerNotified = YES;
        
        NSMutableDictionary *postInfo = [self prepareAPIPostParameter];
        [self notifyServerWithHealthInfo:postInfo];
    }
}

- (NSMutableDictionary *)prepareAPIPostParameter {
    
    NSMutableDictionary *postInfo = [[NSMutableDictionary alloc] init];
    
    [postInfo setObject:@"Unavailable" forKey:@"heartRate"];
    [postInfo setObject:@"Unavailable" forKey:@"bloodPressure"];
    [postInfo setObject:@"Unavailable" forKey:@"movement"];
    [postInfo setObject:@"Unavailable" forKey:@"position"];
    
    if ([_heartBeatRate isKindOfClass:[NSString class]] && _heartBeatRate.length > 0) {
        [postInfo setObject:_heartBeatRate forKey:@"heartRate"];
    }
    
    if ([_bloodpressure isKindOfClass:[NSString class]] && _bloodpressure.length > 0) {
        [postInfo setObject:_bloodpressure forKey:@"bloodPressure"];
    }
    
    if ([_movement isKindOfClass:[NSString class]] && _movement.length > 0) {
        [postInfo setObject:_movement forKey:@"movement"];
    }
    
    if ([_location isKindOfClass:[NSString class]] && _location.length > 0) {
        [postInfo setObject:_location forKey:@"position"];
    }
    
    return postInfo;
}

- (void)notifyServerWithHealthInfo:(NSDictionary *)healthInfo {
    
    NSString *urlToSendNotification = [(NSString *)kAPIBaseURL stringByAppendingString:(NSString *)kAPISendNotification];
    NSMutableURLRequest *requestToAlert = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlToSendNotification]];
    requestToAlert.HTTPMethod = (NSString *)kHTTPMethodPost;
    
    NSDictionary *headers = @{ @"content-type": @"application/x-www-form-urlencoded",
                               @"cache-control": @"no-cache"};
    [requestToAlert setAllHTTPHeaderFields:headers];
    
    if (healthInfo && healthInfo.allKeys.count > 0) {
        NSMutableData *postData = [[NSMutableData alloc] initWithData:[[[NSString alloc] initWithFormat:@"heartRate=%@", [healthInfo objectForKey:@"heartRate"]] dataUsingEncoding:NSUTF8StringEncoding]];
        [postData appendData:[[[NSString alloc] initWithFormat:@"&bloodPressure=%@", [healthInfo objectForKey:@"bloodPressure"]] dataUsingEncoding:NSUTF8StringEncoding]];
        [postData appendData:[[[NSString alloc] initWithFormat:@"&movement=%@", [healthInfo objectForKey:@"movement"]] dataUsingEncoding:NSUTF8StringEncoding]];
        [postData appendData:[[[NSString alloc] initWithFormat:@"&position=%@", [healthInfo objectForKey:@"position"]] dataUsingEncoding:NSUTF8StringEncoding]];
        requestToAlert.HTTPBody = postData;
    }
    
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:requestToAlert completionHandler:^(NSData * data, NSURLResponse * response, NSError * error) {
        
        [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
        
        [self updateStatus:error];
    }];
    
    [dataTask resume];
}

@end
