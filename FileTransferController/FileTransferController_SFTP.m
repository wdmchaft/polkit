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

#import <netinet/in.h>
#import "libssh2.h"
#import "libssh2_sftp.h"

#import "FileTransferController_Internal.h"
#import "NSURL+Parameters.h"

#define kDefaultSSHPort					22
#define kSocketConnectionTimeOut		30.0 //seconds
#define kDefaultMode					0755
#define kNameBufferSize					1024
#define kTransferBufferSize				(32 * 1024)

static CFSocketRef _CreateSocketConnectedToHost(NSString* name, UInt16 port, CFOptionFlags callBackTypes, CFSocketCallBack callback, const CFSocketContext* context)
{
	struct sockaddr_in			ipAddress;
	CFHostRef					host;
	CFStreamError				error;
	NSData*						data;
	const struct sockaddr*		address;
	CFSocketSignature			signature;
	CFSocketRef					socket;
	
	if(!name || !port)
	return NULL;
	
	host = CFHostCreateWithName(kCFAllocatorDefault, (CFStringRef)name);
	if(host) {
		if(CFHostStartInfoResolution(host, kCFHostAddresses, &error)) {
			for(data in (NSArray*)CFHostGetAddressing(host, NULL)) {
				address = (const struct sockaddr*)[data bytes];
				if((address->sa_family == AF_INET) && (address->sa_len == sizeof(ipAddress))) {
					bcopy(address, &ipAddress, address->sa_len);
					ipAddress.sin_port = htons(port);
					port = 0;
					break;
				}
			}
		}
		else
		NSLog(@"%s: CFHostStartInfoResolution() for host \"%@\" failed with error %i", __FUNCTION__, name, error.error);
		CFRelease(host);
	}
	if(port)
	return NULL;
	
	signature.protocolFamily = AF_INET;
	signature.socketType = SOCK_STREAM;
	signature.protocol = IPPROTO_IP;
	signature.address = (CFDataRef)[NSData dataWithBytes:&ipAddress length:ipAddress.sin_len];
	
	socket = CFSocketCreateConnectedToSocketSignature(kCFAllocatorDefault, &signature, callBackTypes, callback, context, kSocketConnectionTimeOut);
	if(socket == NULL)
	NSLog(@"%s: CFSocketCreateConnectedToSocketSignature() failed", __FUNCTION__);
	
	return socket;
}

@implementation SFTPTransferController

+ (NSString*) urlScheme;
{
	return @"ssh";
}

- (id) initWithURL:(NSURL*)url
{
	const char*					user = [[url user] UTF8String];
	const char*					password = [[url passwordByReplacingPercentEscapes] UTF8String];
	char*						message;
	
	if((user == NULL) || (password == NULL)) {
		[self release];
		return nil;
	}
	
	if((self = [super initWithURL:url])) {
		_socket = _CreateSocketConnectedToHost([url host], ([url port] ? [[url port] unsignedShortValue] : kDefaultSSHPort), kCFSocketNoCallBack, NULL, NULL);
		if(_socket) {
			_session = libssh2_session_init();
			if(_session) {
				if(libssh2_session_startup(_session, CFSocketGetNative(_socket)) == 0) {
					if(libssh2_userauth_password(_session, user, password) == 0) {
						_sftp = libssh2_sftp_init(_session);
						if(_sftp == NULL)
						NSLog(@"%s: libssh2_sftp_init() failed", __FUNCTION__);
					}
					else {
						libssh2_session_last_error(_session, &message, NULL, 0);
						NSLog(@"%s: libssh2_userauth_password() failed: %s", __FUNCTION__, message);
					}
				}
				else {
					libssh2_session_last_error(_session, &message, NULL, 0);
					NSLog(@"%s: libssh2_session_startup() failed: %s", __FUNCTION__, message);
				}
			}
			else
			NSLog(@"%s: libssh2_session_init() failed", __FUNCTION__);
		}
		
		if(_sftp == NULL) {
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (void) invalidate
{
	if(_sftp) {
		libssh2_sftp_shutdown(_sftp);
		_sftp = NULL;
	}
	
	if(_session) {
		libssh2_session_free(_session);
		_session = NULL;
	}
	
	if(_socket) {
		CFSocketInvalidate(_socket);
		CFRelease(_socket);
		_socket = NULL;
	}
}

- (BOOL) downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream
{
	BOOL					delegateHasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	const char*				serverPath = [[[[self baseURL] path] stringByAppendingPathComponent:[remotePath stringByStandardizingPath]] UTF8String];
	BOOL					success = NO;
	NSUInteger				length = 0;
	unsigned char			buffer[kTransferBufferSize];
	ssize_t					numBytes;
	LIBSSH2_SFTP_HANDLE*	handle;
	LIBSSH2_SFTP_ATTRIBUTES	attributes;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	handle = libssh2_sftp_open(_sftp, serverPath, LIBSSH2_FXF_READ, 0);
	if(handle) {
		if([self openOutputStream:stream isFileTransfer:YES]) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
			[[self delegate] fileTransferControllerDidStart:self];
			
			if(libssh2_sftp_fstat(handle, &attributes) == 0) {
				if(attributes.flags & LIBSSH2_SFTP_ATTR_SIZE)
				length = attributes.filesize;
			}
			[self setMaxLength:length];
			
			length = 0;
			do {
				numBytes = libssh2_sftp_read(handle, (char*)buffer, kTransferBufferSize);
				if(numBytes > 0) {
					if(![self writeToOutputStream:stream bytes:buffer maxLength:numBytes]) {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:error:)])
						[[self delegate] fileTransferControllerDidFail:self error:MAKE_GENERIC_ERROR(@"Failed writing to file")];
						break;
					}
					
					length += numBytes;
					[self setCurrentLength:length];
				}
				else {
					if(![self flushOutputStream:stream])
					numBytes = -1;
					
					if(numBytes == 0) {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
						[[self delegate] fileTransferControllerDidSucceed:self];
						success = YES;
					}
					else {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:error:)])
						[[self delegate] fileTransferControllerDidFail:self error:MAKE_GENERIC_ERROR(@"Failed reading from SFTP stream (error %i)", libssh2_sftp_last_error(_sftp))];
					}
					break;
				}
			} while(!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]);
			
			[self closeOutputStream:stream];
		}
		
		libssh2_sftp_close(handle);
	}
	
	return success;
}

- (BOOL) uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream
{
	BOOL					delegateHasShouldAbort = [[self delegate] respondsToSelector:@selector(fileTransferControllerShouldAbort:)];
	const char*				serverPath = [[[[self baseURL] path] stringByAppendingPathComponent:[remotePath stringByStandardizingPath]] UTF8String];
	NSUInteger				length = 0;
	BOOL					success = NO;
	LIBSSH2_SFTP_HANDLE*	handle;
	unsigned char			buffer[kTransferBufferSize];
	ssize_t					numBytes,
							result;
	
	if(!stream || ([stream streamStatus] != NSStreamStatusNotOpen))
	return NO;
	
	if([self openInputStream:stream isFileTransfer:YES]) {
		handle = libssh2_sftp_open(_sftp, serverPath, LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC | LIBSSH2_FXF_WRITE, kDefaultMode);
		if(handle) {
			if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidStart:)])
			[[self delegate] fileTransferControllerDidStart:self];
			
			do {
				numBytes = [self readFromInputStream:stream bytes:buffer maxLength:kTransferBufferSize];
				if(numBytes > 0) {
					result = libssh2_sftp_write(handle, (char*)buffer, numBytes);
					if(result != numBytes) {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:error:)])
						[[self delegate] fileTransferControllerDidFail:self error:MAKE_GENERIC_ERROR(@"Failed writing to SFTP stream (error %i)", libssh2_sftp_last_error(_sftp))];
						break;
					}
					
					length += numBytes;
					[self setCurrentLength:length];
				}
				else {
					if(numBytes == 0) {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidSucceed:)])
						[[self delegate] fileTransferControllerDidSucceed:self];
						success = YES;
					}
					else {
						if([[self delegate] respondsToSelector:@selector(fileTransferControllerDidFail:error:)])
						[[self delegate] fileTransferControllerDidFail:self error:MAKE_GENERIC_ERROR(@"Failed reading from file stream")];
					}
					break;
				}
			} while(!delegateHasShouldAbort || ![[self delegate] fileTransferControllerShouldAbort:self]);
			
			libssh2_sftp_close(handle);
		}
		
		[self closeInputStream:stream];
	}
	
	return success;
}

- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath
{
	const char*				serverPath = [[[[self baseURL] path] stringByAppendingPathComponent:[remotePath stringByStandardizingPath]] UTF8String];
	NSMutableDictionary*	listing = [NSMutableDictionary dictionary];
	char					buffer[kNameBufferSize];
	LIBSSH2_SFTP_HANDLE*	handle;
	LIBSSH2_SFTP_ATTRIBUTES	attributes;
	NSMutableDictionary*	dictionary;
	
	handle = libssh2_sftp_opendir(_sftp, serverPath);
	if(handle == NULL) {
		NSLog(@"%s: libssh2_sftp_opendir() failed with error %i", __FUNCTION__, libssh2_sftp_last_error(_sftp));
		return nil;
	}
	
	while(libssh2_sftp_readdir(handle, buffer, kNameBufferSize, &attributes) > 0) {
		if((buffer[0] == '.') && ((buffer[1] == 0) || (buffer[1] == '.')))
		continue;
		if(!(attributes.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS))
		continue; //FIXME: What to do?
		if(S_ISLNK(attributes.permissions))
		continue; //FIXME: We ignore symlinks
		
		dictionary = [NSMutableDictionary new];
		[dictionary setObject:(S_ISDIR(attributes.permissions) ? NSFileTypeDirectory : NSFileTypeRegular) forKey:NSFileType];
		if(attributes.flags & LIBSSH2_SFTP_ATTR_ACMODTIME)
		[dictionary setObject:[NSDate dateWithTimeIntervalSince1970:attributes.mtime] forKey:NSFileModificationDate];
		if(S_ISREG(attributes.permissions) && (attributes.flags & LIBSSH2_SFTP_ATTR_SIZE))
		[dictionary setObject:[NSNumber numberWithUnsignedLongLong:attributes.filesize] forKey:NSFileSize];
		[listing setObject:dictionary forKey:[NSString stringWithUTF8String:buffer]];
		[dictionary release];
	}
	
	libssh2_sftp_closedir(handle);
	
	return listing;
}

- (BOOL) createDirectoryAtPath:(NSString*)remotePath
{
	const char*				serverPath = [[[[self baseURL] path] stringByAppendingPathComponent:[remotePath stringByStandardizingPath]] UTF8String];
	
	if(libssh2_sftp_mkdir(_sftp, serverPath, kDefaultMode)) {
		NSLog(@"%s: libssh2_sftp_mkdir() failed with error %i", __FUNCTION__, libssh2_sftp_last_error(_sftp));
		return NO;
	}
	
	return YES;
}

- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath
{
	const char*				fromPath = [[[[self baseURL] path] stringByAppendingPathComponent:[fromRemotePath stringByStandardizingPath]] UTF8String];
	const char*				toPath = [[[[self baseURL] path] stringByAppendingPathComponent:[toRemotePath stringByStandardizingPath]] UTF8String];
	
	if(libssh2_sftp_rename(_sftp, fromPath, toPath)) {
		NSLog(@"%s: libssh2_sftp_rename() failed with error %i", __FUNCTION__, libssh2_sftp_last_error(_sftp));
		return NO;
	}
	
	return YES;
}

- (BOOL) deleteFileAtPath:(NSString*)remotePath
{
	const char*				serverPath = [[[[self baseURL] path] stringByAppendingPathComponent:[remotePath stringByStandardizingPath]] UTF8String];
	LIBSSH2_SFTP_ATTRIBUTES	attributes;
	
	if(libssh2_sftp_lstat(_sftp, serverPath, &attributes))
	return YES;
	
	if(libssh2_sftp_unlink(_sftp, serverPath)) {
		NSLog(@"%s: libssh2_sftp_unlink() failed with error %i", __FUNCTION__, libssh2_sftp_last_error(_sftp));
		return NO;
	}
	
	return YES;
}

- (BOOL) deleteDirectoryAtPath:(NSString*)remotePath
{
	const char*				serverPath = [[[[self baseURL] path] stringByAppendingPathComponent:[remotePath stringByStandardizingPath]] UTF8String];
	LIBSSH2_SFTP_ATTRIBUTES	attributes;
	
	if(libssh2_sftp_lstat(_sftp, serverPath, &attributes))
	return YES;
	
	if(libssh2_sftp_rmdir(_sftp, serverPath)) {
		NSLog(@"%s: libssh2_sftp_unlink() failed with error %i", __FUNCTION__, libssh2_sftp_last_error(_sftp));
		return NO;
	}
	
	return YES;
}

@end
