/*
	This file is part of the PolKit library.
	Copyright (C) 2008-2009 Pierre-Olivier Latour <info@pol-online.net>
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <openssl/evp.h>

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"
#import "DataStream.h"

#define kStreamBufferSize				(256 * 1024)
#define kRunLoopInterval				1.0
#define kEncryptionCipher				EVP_aes_256_cbc()
#define kEncryptionCipherBlockSize		16
#define kDigestType						EVP_md5()

typedef struct {
	unsigned char*						buffer;
	NSUInteger							size;
} DataInfo;

@implementation FileTransferController

@synthesize baseURL=_baseURL, delegate=_delegate, transferSize=_maxLength, maxLength=_maxLength, currentLength=_currentLength, digestComputation=_digestComputation, encryptionPassword=_encryptionPassword, maximumDownloadSpeed=_maxDownloadSpeed, maximumUploadSpeed=_maxUploadSpeed;

+ (id) allocWithZone:(NSZone*)zone
{
	if(self == [FileTransferController class])
	[[NSException exceptionWithName:NSInternalInconsistencyException reason:@"FileTransferController is an abstract class" userInfo:nil] raise];
	
	return [super allocWithZone:zone];
}

+ (NSString*) urlScheme;
{
	return nil;
}

+ (BOOL) useAsyncStreams
{
	return YES;
}

+ (BOOL) hasAtomicUploads
{
	return NO;
}

+ (FileTransferController*) fileTransferControllerWithURL:(NSURL*)url
{
	NSString*					user = [url user];
	NSString*					password = [url passwordByReplacingPercentEscapes];
	
	if([[url scheme] isEqualToString:@"file"])
	return [[[LocalTransferController alloc] initWithURL:url] autorelease];
	
	if([[url scheme] isEqualToString:@"afp"])
	return [[[AFPTransferController alloc] initWithURL:url] autorelease];
	
	if([[url scheme] isEqualToString:@"smb"])
	return [[[SMBTransferController alloc] initWithURL:url] autorelease];
	
	if([[url scheme] isEqualToString:@"http"]) {
		if([[url host] isEqualToString:kFileTransferHost_iDisk]) {
			if(user && password)
			return [[[WebDAVTransferController alloc] initWithIDiskForUser:user password:password basePath:[url path]] autorelease];
			else if(user)
			return [[[WebDAVTransferController alloc] initWithIDiskForUser:user basePath:[url path]] autorelease];
			else
			return [[[WebDAVTransferController alloc] initWithIDiskForLocalUser:[url path]] autorelease];
		}
		else {
			if([[url host] hasSuffix:kFileTransferHost_AmazonS3])
			return [[[AmazonS3TransferController alloc] initWithURL:url] autorelease];
			else
			return [[[WebDAVTransferController alloc] initWithURL:url] autorelease];
		}
	}
	
	if([[url scheme] isEqualToString:@"https"]) {
		if([[url host] hasSuffix:kFileTransferHost_AmazonS3])
		return [[[SecureAmazonS3TransferController alloc] initWithURL:url] autorelease];
		else
		return [[[SecureWebDAVTransferController alloc] initWithURL:url] autorelease];
	}
	
	if([[url scheme] isEqualToString:@"ftp"])
	return [[[FTPTransferController alloc] initWithURL:url] autorelease];
	
	if([[url scheme] isEqualToString:@"ssh"])
	return [[[SFTPTransferController alloc] initWithURL:url] autorelease];
	
	return nil;
}

- (id) init
{
	return [self initWithURL:nil];
}

- (id) initWithURL:(NSURL*)url
{
	if(![[url scheme] isEqualToString:[[self class] urlScheme]]) {
		[self release];
		return nil;
	}
	
	if((self = [super init]))
	_baseURL = [url copy];
	
	return self;
}

- (id) initWithHost:(NSString*)host port:(UInt16)port username:(NSString*)username password:(NSString*)password basePath:(NSString*)basePath
{
	return [self initWithURL:[NSURL URLWithScheme:[[self class] urlScheme] user:username password:password host:host port:port path:basePath]];
}

- (void) dealloc
{
	[self invalidate];
	
	[_encryptionPassword release];
	[_baseURL release];
	
	[super dealloc];
}

- (void) setMaxLength:(NSUInteger)length
{
	_maxLength = length;
	_currentLength = 0;
}

- (void) setCurrentLength:(NSUInteger)length
{
	if((_maxLength > 0) && (length != _currentLength)) {
		_currentLength = length;
		if([_delegate respondsToSelector:@selector(fileTransferControllerDidUpdateProgress:)])
		[_delegate fileTransferControllerDidUpdateProgress:self];
	}
}

- (float) transferProgress
{
	return (_maxLength > 0 ? MIN((float)_currentLength / (float)_maxLength, 1.0) : NAN);
}

- (NSUInteger) lastTransferSize
{
	return _totalSize;
}

- (NSData*) lastTransferDigestData
{
	unsigned int*			ptr = (unsigned int*)_digestBuffer;
	NSData*					data = nil;
	
	if(ptr[0] && ptr[1] && ptr[2] && ptr[3])
	data = [NSData dataWithBytes:_digestBuffer length:16];
	
	return data;
}

- (void) invalidate
{
	[self doesNotRecognizeSelector:_cmd];
}

- (NSURL*) absoluteURLForRemotePath:(NSString*)path
{
	NSString*					basePath = [_baseURL path];
	
	if([basePath length]) {
		if([path length]) {
			if([basePath hasSuffix:@"/"] || [path hasPrefix:@"/"])
			path = [basePath stringByAppendingString:path];
			else
			path = [basePath stringByAppendingFormat:@"/%@", path];
		}
		else
		path = basePath;
	}
	
	return [NSURL URLWithScheme:[_baseURL scheme] user:nil password:nil host:[_baseURL host] port:[[_baseURL port] unsignedShortValue] path:path];
}

- (BOOL) downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

- (BOOL) uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

- (BOOL) _createDigestContext
{
	bzero(_digestBuffer, 16);
	
	if(_digestComputation) {
		_digestContext = malloc(sizeof(EVP_MD_CTX));
		EVP_DigestInit(_digestContext, kDigestType);
	}
	
	return YES;
}

- (void) _destroyDigestContext
{
	if(_digestContext) {
		free(_digestContext);
		_digestContext = NULL;
	}
}

- (BOOL) _createCypherContext:(BOOL)decrypt
{
	unsigned char				keyBuffer[EVP_MAX_KEY_LENGTH];
	unsigned char				ivBuffer[EVP_MAX_IV_LENGTH];
	NSData*						passwordData;
	
	if(_encryptionPassword) {
		passwordData = [_encryptionPassword dataUsingEncoding:NSUTF8StringEncoding];
		if(![passwordData length])
		return NO;
		
		if(EVP_BytesToKey(kEncryptionCipher, EVP_md5(), NULL, [passwordData bytes], [passwordData length], 1, keyBuffer, ivBuffer) == 0)
		return NO;
		
		_encryptionContext = malloc(sizeof(EVP_CIPHER_CTX));
		EVP_CIPHER_CTX_init(_encryptionContext);
		if((decrypt ? EVP_DecryptInit(_encryptionContext, kEncryptionCipher, keyBuffer, ivBuffer) : EVP_EncryptInit(_encryptionContext, kEncryptionCipher, keyBuffer, ivBuffer)) != 1) {
			EVP_CIPHER_CTX_cleanup(_encryptionContext);
			free(_encryptionContext);
			_encryptionContext = NULL;
			return NO;
		}
		
		_encryptionBufferBytes = malloc(0);
		_encryptionBufferSize = 0;
	}
	
	return YES;
}

- (void) _destroyCypherContext
{
	if(_encryptionContext) {
		free(_encryptionBufferBytes);
		EVP_CIPHER_CTX_cleanup(_encryptionContext);
		free(_encryptionContext);
		_encryptionContext = NULL;
	}
}

- (BOOL) openOutputStream:(NSOutputStream*)stream isFileTransfer:(BOOL)isFileTransfer
{
	_totalSize = 0;
	if(isFileTransfer) {
		if(![self _createDigestContext] || ![self _createCypherContext:YES])
		return NO;
		_maxSpeed = _maxDownloadSpeed;
	}
	else
	_maxSpeed = 0.0;
	
	[stream open];
	if([stream streamStatus] != NSStreamStatusOpen) {
		[self _destroyCypherContext];
		[self _destroyDigestContext];
		return NO;
	}
	
	return YES;
}

- (BOOL) writeToOutputStream:(NSOutputStream*)stream bytes:(const void*)bytes maxLength:(NSUInteger)length
{
	CFAbsoluteTime				time = 0.0;
	BOOL						success = YES;
	int							offset = 0,
								realLength,
								numBytes;
	void*						realBytes;
	
	if(_maxSpeed)
	time = CFAbsoluteTimeGetCurrent();
	
	if(_encryptionContext) {
		if(length + EVP_MAX_BLOCK_LENGTH != _encryptionBufferSize) {
			_encryptionBufferSize = length + EVP_MAX_BLOCK_LENGTH;
			free(_encryptionBufferBytes);
			_encryptionBufferBytes = malloc(_encryptionBufferSize);
		}
		
		realBytes = _encryptionBufferBytes;
		if(EVP_DecryptUpdate(_encryptionContext, realBytes, &realLength, bytes, length) != 1)
		success = NO;
	}
	else {
		realBytes = (void*)bytes;
		realLength = length;
	}
	
	if(success && _digestContext) {
		if(EVP_DigestUpdate(_digestContext, realBytes, realLength) != 1)
		success = NO;
	}
	
	if(success && (realLength - offset > 0)) {
		success = NO;
		while(1) {
			numBytes = [stream write:((const uint8_t*)realBytes + offset) maxLength:(realLength - offset)]; //NOTE: Writing 0 bytes will close the stream
			if(numBytes < 0)
			break;
			offset += numBytes;
			if(offset == realLength) {
				success = YES;
				break;
			}
#ifdef __DEBUG__
			NSLog(@"%s wrote only %i bytes out of %i", __FUNCTION__, numBytes, realLength - offset);
#endif
		}
	}
	
	if(success)
	_totalSize += length;
	
	if(_maxSpeed && success) {
		time = CFAbsoluteTimeGetCurrent() - time;
		time = (double)realLength / _maxSpeed - time;
		if(time > 0)
		usleep(time * 1000000.0);
	}
	
	return success;
}

- (BOOL) flushOutputStream:(NSOutputStream*)stream
{
	BOOL						success = YES;
	int							offset = 0,
								outLength,
								numBytes;
	unsigned char				buffer[EVP_MAX_BLOCK_LENGTH];
	
	if(_encryptionContext) {
		if(EVP_DecryptFinal(_encryptionContext, buffer, &outLength) != 1)
		success = NO;
		
		[self _destroyCypherContext];
		
		if(success) {
			success = NO;
			while(1) {
				numBytes = [stream write:((const uint8_t*)buffer + offset) maxLength:(outLength - offset)];
				if(numBytes < 0)
				break;
				offset += numBytes;
				if(offset == outLength) {
					success = YES;
					break;
				}
#ifdef __DEBUG__
				NSLog(@"%s wrote only %i bytes out of %i", __FUNCTION__, numBytes, outLength - offset);
#endif
			}
		}
		
		if(success && _digestContext) {
			if(EVP_DigestUpdate(_digestContext, buffer, outLength) != 1)
			success = NO;
		}
	}
	
	if(_digestContext) {
		if(success) {
			if(EVP_DigestFinal(_digestContext, _digestBuffer, (unsigned int*)&outLength) != 1)
			success = NO;
		}
		
		[self _destroyDigestContext];
	}
	
	return success;
}

- (void) closeOutputStream:(NSOutputStream*)stream
{
	[self _destroyCypherContext];
	[self _destroyDigestContext];
	
	[stream close];
}

- (BOOL) openInputStream:(NSInputStream*)stream isFileTransfer:(BOOL)isFileTransfer
{
	_totalSize = 0;
	if(isFileTransfer) {
		if(![self _createDigestContext] || ![self _createCypherContext:NO])
		return NO;
		_maxSpeed = _maxUploadSpeed;
	}
	else
	_maxSpeed = 0.0;
	
	[stream open];
	if([stream streamStatus] != NSStreamStatusOpen) {
		[self _destroyCypherContext];
		[self _destroyDigestContext];
		return NO;
	}
	
	return YES;
}

- (NSInteger) readFromInputStream:(NSInputStream*)stream bytes:(void*)bytes maxLength:(NSUInteger)length
{
	CFAbsoluteTime				time = 0.0;
	void*						newBytes;
	int							newLength;
	NSInteger					result;
	
	if(_maxSpeed)
	time = CFAbsoluteTimeGetCurrent();
	
	if(_encryptionContext) {
		if(length <= EVP_MAX_BLOCK_LENGTH)
		return -1;
		
		if(length != _encryptionBufferSize) {
			_encryptionBufferSize = length;
			free(_encryptionBufferBytes);
			_encryptionBufferBytes = malloc(_encryptionBufferSize);
		}
		
		newBytes = _encryptionBufferBytes;
		result = [stream read:newBytes maxLength:(length - EVP_MAX_BLOCK_LENGTH)];
		if(result > 0) {
			if(_digestContext) {
				if(EVP_DigestUpdate(_digestContext, newBytes, result) != 1)
				result = -1;
			}
			
			if(result > 0) {
				if(EVP_EncryptUpdate(_encryptionContext, bytes, &newLength, newBytes, result) == 1) //FIXME: We should encrypt directly into "bytes" if there's enough room
				result = newLength;
				else
				result = -1;
			}
		}
		if(result == 0) { //HACK: CFReadStreamCreateForStreamedHTTPRequest() will stop reading when reaching Content-Length, so NSInputStream may never have an opportunity to return 0
			if(_digestContext) {
				if(EVP_DigestFinal(_digestContext, _digestBuffer, (unsigned int*)&newLength) != 1)
				result = -1;
			}
			
			if(result == 0) {
				if(EVP_EncryptFinal(_encryptionContext, bytes, &newLength) == 1)
				result = newLength;
				else
				result = -1;
			}
			
			[self _destroyCypherContext];
			[self _destroyDigestContext];
		}
	}
	else {
		result = [stream read:bytes maxLength:length];
		
		if(_digestContext) {
			if(result > 0) {
				if(EVP_DigestUpdate(_digestContext, bytes, result) != 1)
				result = -1;
			}
			if((result == 0) || (_currentLength + result == _maxLength)) { //HACK: CFReadStreamCreateForStreamedHTTPRequest() will stop reading when reaching Content-Length, so NSInputStream may never have an opportunity to return 0
				if(EVP_DigestFinal(_digestContext, _digestBuffer, (unsigned int*)&newLength) != 1)
				result = -1;
				
				[self _destroyDigestContext];
			}
		}
	}
	
	if(result > 0)
	_totalSize += result;
	
	if(_maxSpeed && (result > 0)) {
		time = CFAbsoluteTimeGetCurrent() - time;
		time = (double)result / _maxSpeed - time;
		if(time > 0)
		usleep(time * 1000000.0);
	}
		
	return result;
}

- (void) closeInputStream:(NSInputStream*)stream
{
	[self _destroyCypherContext];
	[self _destroyDigestContext];
	
	[stream close];
}

@end

@implementation FileTransferController (Extensions)

- (BOOL) uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream length:(NSUInteger)length
{
	BOOL					success;
	
	if([self encryptionPassword])
	length = (length / kEncryptionCipherBlockSize + 1) * kEncryptionCipherBlockSize;
	[self setMaxLength:length];
	
	success = [self uploadFileToPath:remotePath fromStream:stream];
	
	[self setMaxLength:0];
	
	return success;
}

- (BOOL) downloadFileFromPathToNull:(NSString*)remotePath
{
	return [self downloadFileFromPath:remotePath toStream:[NSOutputStream outputStreamToFileAtPath:@"/dev/null" append:NO]];
}

- (BOOL) downloadFileFromPath:(NSString*)remotePath toPath:(NSString*)localPath
{
	NSOutputStream*			stream;
	BOOL					success;
	NSError*				error;
	
	localPath = [localPath stringByStandardizingPath];
	stream = [NSOutputStream outputStreamToFileAtPath:localPath append:NO];
	if(stream == nil)
	return NO;
	
	success = [self downloadFileFromPath:remotePath toStream:stream];
	
	if(!success && ([stream streamStatus] > NSStreamStatusNotOpen)) {
		if(![[NSFileManager defaultManager] removeItemAtPath:localPath error:&error])
		NSLog(@"%@: %@", __FUNCTION__, error);
	}
	
	return success;
}

- (BOOL) uploadFileFromPath:(NSString*)localPath toPath:(NSString*)remotePath
{
	NSDictionary*			info;
	BOOL					success;
	NSUInteger				maxLength;
	
	localPath = [localPath stringByStandardizingPath];
	info = [[NSFileManager defaultManager] fileAttributesAtPath:localPath traverseLink:YES];
	if(info == nil)
	return NO;
	
	maxLength = [[info objectForKey:NSFileSize] unsignedIntegerValue];
	if([self encryptionPassword])
	maxLength = (maxLength / kEncryptionCipherBlockSize + 1) * kEncryptionCipherBlockSize;
	[self setMaxLength:maxLength];
	
	success = [self uploadFileToPath:remotePath fromStream:[NSInputStream inputStreamWithFileAtPath:localPath]];
	
	[self setMaxLength:0];
	
	return success;
}

- (NSData*) downloadFileFromPathToData:(NSString*)remotePath
{
	NSOutputStream*			stream;
	
	stream = [NSOutputStream outputStreamToMemory];
	if(stream == nil)
	return nil;
	
	return ([self downloadFileFromPath:remotePath toStream:stream] ? [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey] : nil);
}

- (BOOL) uploadFileFromData:(NSData*)data toPath:(NSString*)remotePath
{
	BOOL					success;
	NSUInteger				maxLength;
	
	if(data == nil)
	return NO;
	
	maxLength = [data length];
	if([self encryptionPassword])
	maxLength = (maxLength / kEncryptionCipherBlockSize + 1) * kEncryptionCipherBlockSize;
	[self setMaxLength:maxLength];
	
	success = [self uploadFileToPath:remotePath fromStream:[NSInputStream inputStreamWithData:data]];
	
	[self setMaxLength:0];
	
	return success;
}

- (BOOL) openDataStream:(id)userInfo
{
	return YES;
}

- (NSInteger) readDataFromStream:(id)userInfo buffer:(void*)buffer maxLength:(NSUInteger)length
{
	DataInfo*				info = (DataInfo*)[userInfo pointerValue];
	
	length = MIN(length, info->size);
	bcopy(info->buffer, buffer, length);
	info->buffer += length;
	info->size -= length;
	
	return length;
}

- (NSInteger) writeDataToStream:(id)userInfo buffer:(const void*)buffer maxLength:(NSUInteger)length
{
	DataInfo*				info = (DataInfo*)[userInfo pointerValue];
	
	length = MIN(length, info->size);
	bcopy(buffer, info->buffer, length);
	info->buffer += length;
	info->size -= length;
	
	return length;
}

- (void) closeDataStream:(id)userInfo
{
	;
}

- (NSInteger) downloadFileFromPath:(NSString*)remotePath toBuffer:(void*)buffer capacity:(NSUInteger)capacity
{
	BOOL					success;
	DataWriteStream*		writeStream;
	DataInfo				info;
	
	if(buffer == NULL)
	return -1;
	
	info.buffer = (void*)buffer;
	info.size = capacity;
	writeStream = [[DataWriteStream alloc] initWithDataDestination:(id<DataStreamDestination>)self userInfo:[NSValue valueWithPointer:&info]];
	success = [self downloadFileFromPath:remotePath toStream:writeStream];
	[writeStream release];
	
	return (success ? capacity - info.size : -1);
}

- (BOOL) uploadFileFromBytes:(const void*)bytes length:(NSUInteger)length toPath:(NSString*)remotePath
{
	BOOL					success;
	NSUInteger				maxLength;
	DataReadStream*			readStream;
	DataInfo				info;
	
	if(bytes == NULL)
	return NO;
	
	maxLength = length;
	if([self encryptionPassword])
	maxLength = (maxLength / kEncryptionCipherBlockSize + 1) * kEncryptionCipherBlockSize;
	[self setMaxLength:maxLength];
	
	info.buffer = (void*)bytes;
	info.size = length;
	readStream = [[DataReadStream alloc] initWithDataSource:(id<DataStreamSource>)self userInfo:[NSValue valueWithPointer:&info]];
	success = [self uploadFileToPath:remotePath fromStream:readStream];
	[readStream release];
	
	[self setMaxLength:0];
	
	return success;
}

@end

@implementation StreamTransferController

@synthesize activeStream=_activeStream;

+ (id) allocWithZone:(NSZone*)zone
{
	if(self == [StreamTransferController class])
	[[NSException exceptionWithName:NSInternalInconsistencyException reason:@"StreamTransferController is an abstract class" userInfo:nil] raise];
	
	return [super allocWithZone:zone];
}

- (id) initWithURL:(NSURL*)url
{
	if((self = [super initWithURL:url]))
	_streamBuffer = malloc(kStreamBufferSize);
	
	return self;
}

- (void) dealloc
{
	[self invalidate];
	
	if(_streamBuffer)
	free(_streamBuffer);
	
	[super dealloc];
}

- (void) invalidate
{
	[_userInfo release];
	_userInfo = nil;
	
	if([_dataStream isKindOfClass:[NSInputStream class]])
	[self closeInputStream:_dataStream];
	else if([_dataStream isKindOfClass:[NSOutputStream class]])
	[self closeOutputStream:_dataStream];
	[_dataStream release];
	_dataStream = nil;
	
	if(_activeStream) {
		if(CFGetTypeID(_activeStream) == CFReadStreamGetTypeID()) {
			if([[self class] useAsyncStreams]) {
				CFReadStreamUnscheduleFromRunLoop((CFReadStreamRef)_activeStream, CFRunLoopGetCurrent(), kFileTransferRunLoopMode);
				CFReadStreamSetClient((CFReadStreamRef)_activeStream, kCFStreamEventNone, NULL, NULL);
			}
			CFReadStreamClose((CFReadStreamRef)_activeStream);
		}
		else if(CFGetTypeID(_activeStream) == CFWriteStreamGetTypeID()) {
			if([[self class] useAsyncStreams]) {
				CFWriteStreamUnscheduleFromRunLoop((CFWriteStreamRef)_activeStream, CFRunLoopGetCurrent(), kFileTransferRunLoopMode);
				CFWriteStreamSetClient((CFWriteStreamRef)_activeStream, kCFStreamEventNone, NULL, NULL);
			}
			CFWriteStreamClose((CFWriteStreamRef)_activeStream);
		}
		CFRelease(_activeStream);
		_activeStream = NULL;
	}
}

static void _ReadStreamClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void* clientCallBackInfo)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	
	[(StreamTransferController*)clientCallBackInfo readStreamClientCallBack:stream type:type];
	
	[pool release];
}

- (void) _doneWithResult:(id)result
{
	[self invalidate];
	
	if(result) {
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
		[[self delegate] fileTransferControllerDidSucceed:self];
	}
	
	_result = [result retain];
	CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void) readStreamClientCallBack:(CFReadStreamRef)stream type:(CFStreamEventType)type
{
	id							result;
	NSError*					error;
	BOOL						success;
	
	switch(type) {
		
		case kCFStreamEventOpenCompleted:
		break;
		
		case kCFStreamEventHasBytesAvailable:
		_transferLength = CFReadStreamRead(stream, _streamBuffer, kStreamBufferSize);
		if(_transferLength > 0) {
			if(_dataStream && ![self writeToOutputStream:_dataStream bytes:_streamBuffer maxLength:_transferLength]) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)]) {
					error = [_dataStream streamError];
					[[self delegate] fileTransferControllerDidFail:self withError:([error code] ? error : MAKE_ERROR([_dataStream streamStatus], @"Failed writing to data stream"))];
				}
				[self _doneWithResult:nil];
			}
			
			[self setCurrentLength:([self currentLength] + _transferLength)];
		}
		break;
		
		case kCFStreamEventErrorOccurred:
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:[(id)CFReadStreamCopyError(stream) autorelease]];
		[self _doneWithResult:nil];
		break;
		
		case kCFStreamEventEndEncountered:
		if(_dataStream) {
			success = [self flushOutputStream:_dataStream];
			[self closeOutputStream:_dataStream];
			if(success == NO) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)]) {
					error = [_dataStream streamError];
					[[self delegate] fileTransferControllerDidFail:self withError:([error code] ? error : MAKE_ERROR([_dataStream streamStatus], @"Failed flushing data stream"))];
				}
				[self _doneWithResult:nil];
				break;
			}
		}
		result = [self processReadResultStream:_dataStream userInfo:_userInfo error:&error];
		if(result == nil) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
			[[self delegate] fileTransferControllerDidFail:self withError:error];
		}
		[self _doneWithResult:result];
		break;
		
	}
}

/* This method takes ownership of the output stream */
- (id) runReadStream:(CFReadStreamRef)readStream dataStream:(NSOutputStream*)dataStream userInfo:(id)info isFileTransfer:(BOOL)allowEncryption
{
	BOOL					delegateHasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	CFStreamClientContext	context = {0, self, NULL, NULL, NULL};
	id						result;
	SInt32					value;
	
	if(dataStream && ![self openOutputStream:dataStream isFileTransfer:allowEncryption]) {
		CFRelease(readStream);
		return nil;
	}
	
	if([[self class] useAsyncStreams]) {
		CFReadStreamSetClient(readStream, kCFStreamEventOpenCompleted | kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, _ReadStreamClientCallBack, &context);
		CFReadStreamScheduleWithRunLoop(readStream, CFRunLoopGetCurrent(), kFileTransferRunLoopMode);
	}
	CFReadStreamOpen(readStream);
	
	_activeStream = readStream;
	_dataStream = [dataStream retain];
	_userInfo = [info retain];
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	_result = nil;
	if([[self class] useAsyncStreams]) {
		do {
			value = CFRunLoopRunInMode(kFileTransferRunLoopMode, kRunLoopInterval, true);
		} while(_activeStream && (value != kCFRunLoopRunStopped) && (value != kCFRunLoopRunFinished) && (!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]));
	}
	else {
		do {
			switch(CFReadStreamGetStatus(readStream)) {
				
				case kCFStreamStatusOpen:
				[self readStreamClientCallBack:readStream type:kCFStreamEventOpenCompleted];
				[self readStreamClientCallBack:readStream type:kCFStreamEventHasBytesAvailable];
				break;
				
				case kCFStreamStatusAtEnd:
				[self readStreamClientCallBack:readStream type:kCFStreamEventEndEncountered];
				readStream = NULL;
				break;
				
				case kCFStreamStatusError:
				[self readStreamClientCallBack:readStream type:kCFStreamEventErrorOccurred];
				readStream = NULL;
				break;
				
				case kCFStreamStatusClosed:
				readStream = NULL;
				break;
				
			}
		} while(readStream && (!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]));
	}
	result = [_result autorelease];
	_result = nil;
	[self invalidate];
	
	return result;
}

- (id) processReadResultStream:(NSOutputStream*)stream userInfo:(id)info error:(NSError**)error
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

static void _WriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void* clientCallBackInfo)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	
	[(StreamTransferController*)clientCallBackInfo writeStreamClientCallBack:stream type:type];
	
	[pool release];
}

- (void) writeStreamClientCallBack:(CFWriteStreamRef)stream type:(CFStreamEventType)type
{
	CFIndex						count;
	
	switch(type) {
		
		case kCFStreamEventOpenCompleted:
		break;
		
		case kCFStreamEventCanAcceptBytes:
		if(_transferOffset == 0) {
			_transferLength = (_dataStream ? [self readFromInputStream:_dataStream bytes:_streamBuffer maxLength:kStreamBufferSize] : 0);
			if(_transferLength < 0) {
				if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
				[[self delegate] fileTransferControllerDidFail:self withError:MAKE_GENERIC_ERROR(@"Failed reading from data stream")];
				[self _doneWithResult:nil];
			}
		}
		if(_transferLength >= 0) {
			count = CFWriteStreamWrite(stream, _streamBuffer + _transferOffset, _transferLength - _transferOffset); //Writing zero bytes will end the stream
			if(count > 0) {
				_transferOffset += count;
				if(_transferOffset == _transferLength)
				_transferOffset = 0;
				[self setCurrentLength:([self currentLength] + count)];
			}
		}
		break;
		
		case kCFStreamEventErrorOccurred:
		if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:withError:)])
		[[self delegate] fileTransferControllerDidFail:self withError:[(id)CFWriteStreamCopyError(stream) autorelease]];
		[self _doneWithResult:nil];
		break;
		
		case kCFStreamEventEndEncountered:
#if 1 //FIXME: Workaround CF FTP not closing upload connection properly (radr://6078711)
		if([self isKindOfClass:[FTPTransferController class]])
		sleep(5);
#endif
		if(_dataStream)
		[self closeInputStream:_dataStream];
		[self _doneWithResult:[NSNumber numberWithBool:YES]];
		break;
		
	}
}

/* This method takes ownership of the output stream */
- (id) runWriteStream:(CFWriteStreamRef)writeStream dataStream:(NSInputStream*)dataStream userInfo:(id)info isFileTransfer:(BOOL)allowEncryption
{
	BOOL					delegateHasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	CFStreamClientContext	context = {0, self, NULL, NULL, NULL};
	id						result;
	SInt32					value;
	
	if(dataStream && ![self openInputStream:dataStream  isFileTransfer:allowEncryption]) {
		CFRelease(writeStream);
		return nil;
	}
	
	if([[self class] useAsyncStreams]) {
		CFWriteStreamSetClient(writeStream, kCFStreamEventOpenCompleted | kCFStreamEventCanAcceptBytes | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, _WriteStreamClientCallBack, &context);
		CFWriteStreamScheduleWithRunLoop(writeStream, CFRunLoopGetCurrent(), kFileTransferRunLoopMode);
	}
	CFWriteStreamOpen(writeStream);
	
	_activeStream = writeStream;
	_dataStream = [dataStream retain];
	_userInfo = [info retain];
	_transferOffset = 0;
	
	if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
	[[self delegate] fileTransferControllerDidStart:self];
	
	_result = nil;
	if([[self class] useAsyncStreams]) {
		do {
			value = CFRunLoopRunInMode(kFileTransferRunLoopMode, kRunLoopInterval, true);
		} while(_activeStream && (value != kCFRunLoopRunStopped) && (value != kCFRunLoopRunFinished) && (!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]));
	}
	else {
		do {
			switch(CFWriteStreamGetStatus(writeStream)) {
				
				case kCFStreamStatusOpen:
				[self writeStreamClientCallBack:writeStream type:kCFStreamEventOpenCompleted];
				[self writeStreamClientCallBack:writeStream type:kCFStreamEventCanAcceptBytes];
				break;
				
				case kCFStreamStatusAtEnd:
				[self writeStreamClientCallBack:writeStream type:kCFStreamEventEndEncountered];
				writeStream = NULL;
				break;
				
				case kCFStreamStatusError:
				[self writeStreamClientCallBack:writeStream type:kCFStreamEventErrorOccurred];
				writeStream = NULL;
				break;
				
				case kCFStreamStatusClosed:
				writeStream = NULL;
				break;
				
			}
		} while(writeStream && (!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]));
	}	
	result = [_result autorelease];
	_result = nil;
	[self invalidate];
	
	return result;
}

@end
