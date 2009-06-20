/*

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple Inc.
("Apple") in consideration of your agreement to the following terms, and your
use, installation, modification or redistribution of this Apple software
constitutes acceptance of these terms.  If you do not agree with these terms,
please do not use, install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and subject
to these terms, Apple grants you a personal, non-exclusive license, under
Apple's copyrights in this original Apple software (the "Apple Software"), to
use, reproduce, modify and redistribute the Apple Software, with or without
modifications, in source and/or binary forms; provided that if you redistribute
the Apple Software in its entirety and without modifications, you must retain
this notice and the following text and disclaimers in all such redistributions
of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc. may be used
to endorse or promote products derived from the Apple Software without specific
prior written permission from Apple.  Except as expressly stated in this notice,
no other rights or licenses, express or implied, are granted by Apple herein,
including but not limited to any patent rights that may be infringed by your
derivative works or by other works in which the Apple Software may be
incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR
DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF
CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF
APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2008 Apple Inc. All Rights Reserved.

*/

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <CFNetwork/CFNetwork.h>
#else
#import <CoreServices/CoreServices.h>
#endif
#import <sys/socket.h>

//CLASSES:

@class TCPConnection;

//PROTOCOLS:

@protocol TCPConnectionDelegate <NSObject>
@optional
- (void) connectionDidFailOpening:(TCPConnection*)connection;
- (void) connectionDidOpen:(TCPConnection*)connection;
- (void) connectionDidClose:(TCPConnection*)connection;

- (void) connection:(TCPConnection*)connection didReceiveData:(NSData*)data;
@end

//CLASS INTERFACES:

/*
This class acts as a controller for TCP based network connections.
The TCPConnection instance will use the current runloop at its time of creation.
*/
@interface TCPConnection : NSObject
{
@private
	CFReadStreamRef				_inputStream;
	CFWriteStreamRef			_outputStream;
	CFRunLoopRef				_runLoop;
	id<TCPConnectionDelegate>	_delegate;
	NSUInteger					_delegateMethods;
	NSUInteger					_opened;
	struct sockaddr*			_localAddress;
	struct sockaddr*			_remoteAddress;
	BOOL						_invalidating;
}
- (id) initWithSocketHandle:(int)socket; //Acquires ownership of the socket
- (id) initWithRemoteAddress:(const struct sockaddr*)address;
- (id) initWithRemoteIPv4Address:(UInt32)address port:(UInt16)port; //The "address" is assumed to be in host-endian
#ifndef __CODEX__
#if !TARGET_OS_IPHONE
- (id) initWithRemoteIPv6Address:(const struct in6_addr*)address port:(UInt16)port;
#endif
#endif
- (id) initWithRemoteHostName:(NSString*)name port:(UInt16)port;
- (id) initWithCFNetService:(CFNetServiceRef)service timeOut:(NSTimeInterval)timeOut; //Pass a negative value if you don't want to attempt to resolve the CFNetService, or zero for an infinite timeout
- (id) initWithServiceDomain:(NSString*)domain type:(NSString*)type name:(NSString*)name timeOut:(NSTimeInterval)timeOut; //Pass a negative value if you don't want to attempt to resolve the CFNetService, or zero for an infinite timeout

@property(nonatomic, assign) id<TCPConnectionDelegate> delegate;

@property(nonatomic, readonly, getter=isValid) BOOL valid;
- (void) invalidate; //Close the connection

@property(nonatomic, readonly) UInt16 localPort;
@property(nonatomic, readonly) UInt32 localIPv4Address; //The returned address is in host-endian
@property(nonatomic, readonly) NSString* localAddress;
@property(nonatomic, readonly) UInt16 remotePort;
@property(nonatomic, readonly) UInt32 remoteIPv4Address; //The returned address is in host-endian
@property(nonatomic, readonly) NSString* remoteAddress;

@property(nonatomic, readonly) const struct sockaddr* remoteSocketAddress;

- (BOOL) sendData:(NSData*)data; //Blocking - Must be called from same thread the connection was created on
- (BOOL) hasDataAvailable; //Non-blocking - Must be called from same thread the connection was created on
- (NSData*) receiveData; //Blocking - Must be called from same thread the connection was created on
@end
