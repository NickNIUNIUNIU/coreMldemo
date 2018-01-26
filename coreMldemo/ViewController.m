//
//  ViewController.m
//  coreMldemo
//
//  Created by niudengjun on 2018/1/18.
//  Copyright © 2018年 niudengjun. All rights reserved.
//

#import "ViewController.h"
#import "Resnet50.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) AVCaptureDevice *captureDevice;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureInput *currentInput;
@property (nonatomic, strong) AVCaptureOutput *currentOutput;

@property (nonatomic, strong) dispatch_queue_t captureQueue;

@property (nonatomic, strong) VNRequest * visionCoreMLRequest;

@property (nonatomic, strong) VNSequenceRequestHandler * sequenceRequestHandler;

@property (nonatomic, strong) UILabel *label1;

@property (nonatomic, assign) NSUInteger num;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
    
    Resnet50 *model = [[Resnet50 alloc]init];
    
    _captureQueue = dispatch_queue_create("com.wutian.CaptureQueue", DISPATCH_QUEUE_SERIAL);
    _session = [[AVCaptureSession alloc] init];
    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
    [self.view.layer addSublayer:_previewLayer];
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [videoOutput setSampleBufferDelegate:self queue:_captureQueue];
    [videoOutput setAlwaysDiscardsLateVideoFrames:YES];
    [videoOutput setVideoSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    _session.sessionPreset = AVCaptureSessionPresetHigh;
    _currentOutput = videoOutput;
    [_session addOutput:videoOutput];
    [_session startRunning];


    
    VNCoreMLModel *visionModel = [VNCoreMLModel modelForMLModel:model.model error:NULL];
    VNCoreMLRequest *classificationRequest = [[VNCoreMLRequest alloc] initWithModel:visionModel completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        
        
        if (error) {
            return NSLog(@"Failed: %@", error);
        }
        NSArray *observations = request.results;
        if (!observations.count) {
            return NSLog(@"No Results");
        }
        
        VNClassificationObservation * observation = nil;
        for (VNClassificationObservation * ob in observations) {
            if (![ob isKindOfClass:[VNClassificationObservation class]]) {
                continue;
            }
            if (!observation) {
                observation = ob;
                continue;
            }
            if (observation.confidence < ob.confidence) {
                observation = ob;
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString * text = [NSString stringWithFormat:@"%@ (%.0f%%)", [[observation.identifier componentsSeparatedByString:@", "] firstObject], observation.confidence * 100];
            NSLog(@"%@",text);
            self.label1.text = text;
        });
    }];
    
    _visionCoreMLRequest = classificationRequest;
    

        [_session beginConfiguration];
        
        if (_currentInput) {
            [_session removeInput:_currentInput];
            _currentInput = nil;
        }
        
        AVCaptureDevice *camera = [self deviceWithPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *cameraInput = [AVCaptureDeviceInput deviceInputWithDevice:camera error:NULL];
        _currentInput = cameraInput;
        [_session addInput:cameraInput];
        
        AVCaptureConnection *conn = [_currentOutput connectionWithMediaType:AVMediaTypeVideo];
        conn.videoOrientation = AVCaptureVideoOrientationPortrait;
        [_session commitConfiguration];
    
    UILabel *label = [[UILabel alloc]initWithFrame:CGRectMake(0, self.view.bounds.size.height - 44, self.view.bounds.size.width, 44)];
    label.backgroundColor = [[UIColor whiteColor]colorWithAlphaComponent:0.6];
    label.font = [UIFont systemFontOfSize:24];
    label.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:label];
    self.label1 = label;
    
}

- (AVCaptureDevice *)deviceWithPosition:(AVCaptureDevicePosition)position
{
    return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:position];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    _num ++;
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) {
        return;
    }
    
    AVCaptureInput * input = connection.inputPorts.firstObject.input;
    if (input != _currentInput) {
        return;
    }
    
    NSMutableDictionary * requestOptions = [NSMutableDictionary dictionary];
    CFTypeRef cameraIntrinsicData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil);
    if (cameraIntrinsicData) {
        requestOptions[VNImageOptionCameraIntrinsics] = (__bridge NSData *)cameraIntrinsicData;
    }
    
    if (!_sequenceRequestHandler) {
        _sequenceRequestHandler = [[VNSequenceRequestHandler alloc] init];
    }
    
    if (_num % 80 == 0) {
        [_sequenceRequestHandler performRequests:@[_visionCoreMLRequest] onCVPixelBuffer:pixelBuffer error:NULL];
        if (_num > 80000) {
            _num = 0;
        }
    }
}

- (void)viewWillLayoutSubviews{
    _previewLayer.frame = self.view.bounds;
}







- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image
{
    NSDictionary *options = @{
                              (NSString*)kCVPixelBufferCGImageCompatibilityKey : @YES,
                              (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                              (NSString*)kCVPixelBufferIOSurfacePropertiesKey: [NSDictionary dictionary]
                              };
    CVPixelBufferRef pxbuffer = NULL;
    
    CGFloat frameWidth = CGImageGetWidth(image);
    CGFloat frameHeight = CGImageGetHeight(image);
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          frameWidth,
                                          frameHeight,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(pxdata,
                                                 frameWidth,
                                                 frameHeight,
                                                 8,
                                                 CVPixelBufferGetBytesPerRow(pxbuffer),
                                                 rgbColorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformIdentity);
    CGContextDrawImage(context, CGRectMake(0,
                                           0,
                                           frameWidth,
                                           frameHeight),
                       image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}



@end
