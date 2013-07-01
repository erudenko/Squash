//
//  SMSquashLayer.m
//  Squash
//
//  Created by Joel Kraut on 6/30/13.
//  Copyright (c) 2013 Joel Kraut. All rights reserved.
//

#import "SMSquashLayer.h"

NSString * const kSquashActionKey = @"_animator";

@interface SMSquashLayer() {
	CFTimeInterval lastFrameTime;
	CFTimeInterval lastTimeDelta;
	CGPoint lastPosition;
	float lastZPosition;
	CATransform3D lastTransform;
	float average[3];
}

@property (nonatomic, assign) float _animator;

- (void)respondTo3dPosition:(float)x :(float)y :(float)z;

@end

@implementation SMSquashLayer

@dynamic _animator;

#pragma mark - Life cycle

- (id)init
{
	if ((self = [super init]))
	{
		self.squashFactor = 3000.f;
		self.maxStretch = 1.5f;
		self.minSquash = .5f;
		lastPosition = (CGPoint){NAN, NAN};
		lastZPosition = NAN;
		lastTransform = CATransform3DIdentity;
		self.smoothMotion = NO;
	}
	return self;
}

#pragma mark - Animation triggers

- (void)setPosition:(CGPoint)position
{
	[super setPosition:position];
	if (isnan(lastPosition.x) || CGSizeEqualToSize(self.frame.size, CGSizeZero))
	{
		lastPosition = position;
		lastZPosition = self.zPosition;
	}
	else
	{
		lastFrameTime = CACurrentMediaTime();
		self._animator = self._animator ? 0.f : 1.f;
	}
}

- (void)setZPosition:(CGFloat)zPosition
{
	[super setZPosition:zPosition];
	if (isnan(lastPosition.x))
	{
		lastPosition = self.position;
		lastZPosition = zPosition;
	}
	else
	{
		self._animator = self._animator ? 0.f : 1.f;
	}
}

#pragma mark - Internal logic

- (void)animationEnded
{
	lastPosition = self.position;
	lastZPosition = self.zPosition;
	average[0] = 0;
	average[1] = 0;
	average[2] = 0;
}

- (void)display
{
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	CALayer *presentationLayer = (CALayer*)self.presentationLayer;
	[self respondTo3dPosition:presentationLayer.position.x :presentationLayer.position.y :presentationLayer.zPosition];
	[CATransaction commit];
	
	[SMSquashLayer cancelPreviousPerformRequestsWithTarget:self selector:@selector(animationEnded) object:nil];
	[self performSelector:@selector(animationEnded) withObject:nil afterDelay:5./60.];
}

static inline void cross(float *b, float *c, float *result)
{
	result[0] = b[1] * c[2] - b[2] * c[1];
	result[1] = b[2] * c[0] - b[0] * c[2];
	result[2] = b[0] * c[1] - b[1] * c[0];
}

static inline void normalize(float *vec)
{
	float magnitude = sqrtf(vec[0] * vec[0] + vec[1] * vec[1] + vec[2] * vec[2]);
	vec[0] /= magnitude;
	vec[1] /= magnitude;
	vec[2] /= magnitude;
}

- (void)respondTo3dPosition:(float)x :(float)y :(float)z
{
	CFTimeInterval now = CACurrentMediaTime();
	
	float delta[3] = {x - lastPosition.x, y - lastPosition.y, z - lastZPosition};
	
	if (self.smoothMotion)
	{
		float averageFactor = .9f;
		average[0] = average[0] * averageFactor + delta[0] * (1.f - averageFactor);
		average[1] = average[1] * averageFactor + delta[1] * (1.f - averageFactor);
		average[2] = average[2] * averageFactor + delta[2] * (1.f - averageFactor);
		
		delta[0] = average[0];
		delta[1] = average[1];
		delta[2] = average[2];
	}
	
	if (delta[0] == 0 && delta[1] == 0 && delta[2] == 0)
		return;
	
	CFTimeInterval timeDelta = lastTimeDelta;
	
	// the current time can be somewhat variable, so let's snap to the nearest frame
	timeDelta *= 60.;
	timeDelta = round(timeDelta);
	timeDelta /= 60.;
	
	// if this is our first frame, let's take a guess as to the time step
	if (timeDelta >= now)
		timeDelta = 1./60.;
	if (timeDelta == 0)
		timeDelta = 1./60.;
		
	float velocity[3] = {delta[0] / timeDelta, delta[1] / timeDelta, delta[2] / timeDelta};
	
	float magnitude = sqrtf(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2]);
	NSLog(@"position delta %.2f\ttime delta %.4f\tmagnitude %.2f", delta[1], timeDelta, magnitude);
	// create a "look at" matrix to orient us along our direction of travel (code modified from gluLookAt)
	normalize(velocity);
	
	CATransform3D squash = CATransform3DIdentity;
	
	float up[3] = {0, 0, -1};
	float side[3];
	cross(velocity, up, side);
	normalize(side);
	cross(side, velocity, up);
	
	squash.m11 = side[0];
	squash.m21 = side[1];
	squash.m31 = side[2];
	squash.m41 = 0;
	
	squash.m12 = up[0];
	squash.m22 = up[1];
	squash.m32 = up[2];
	squash.m42 = 0;
	
	squash.m13 = -velocity[0];
	squash.m23 = -velocity[1];
	squash.m33 = -velocity[2];
	squash.m43 = 0;
	
	// apply a scale in the direction of travel and the directions perpindicular to travel
	CATransform3D squashInverse = CATransform3DInvert(squash);
	
	float scale[3] = {MAX(self.minSquash, MIN(1.f, self.squashFactor / magnitude)),
					  MAX(self.minSquash, MIN(1.f, self.squashFactor / magnitude)),
					  MIN(self.maxStretch, MAX(1.f, magnitude / self.squashFactor))};
//	NSLog(@"scale %.2f %.2f %.2f", scale[0], scale[1], scale[2]);

	CATransform3D scaleTransform = CATransform3DMakeScale(scale[0], scale[1], scale[2]);
	
	squash = CATransform3DConcat(squash, scaleTransform);
	
	squash = CATransform3DConcat(squash, squashInverse);
	
	// apply the squash transform
	self.transform = CATransform3DConcat(self.transform, CATransform3DInvert(lastTransform));
	self.transform = CATransform3DConcat(self.transform, squash);
//	self.transform = squash;
	
	// set new state for next frame
	lastPosition = (CGPoint){x, y};
	lastZPosition = z;
	lastTimeDelta = now - lastFrameTime;
	lastFrameTime = now;
	lastTransform = squash;
}

#pragma mark - Animation Methods

+ (BOOL)needsDisplayForKey:(NSString *)key
{
	if ([key isEqualToString:kSquashActionKey])
		return YES;
	return [super needsDisplayForKey:key];
}

+ (id<CAAction>)defaultActionForKey:(NSString *)key
{
	if ([key isEqualToString:kSquashActionKey])
	{
		CABasicAnimation *animation = [CABasicAnimation animation];
		return animation;
	}
	return [super defaultActionForKey:key];
}

@end
