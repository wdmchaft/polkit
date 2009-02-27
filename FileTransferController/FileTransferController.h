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

#import <Foundation/Foundation.h>

#define kFileTransferHost_Local					@"localhost"
#define kFileTransferHost_iDisk					@"idisk.mac.com"
#define kFileTransferHost_AmazonS3				@"s3.amazonaws.com"

#define kAmazonS3BucketLocation_Europe			@"EU"
#define kAmazonS3ActivationInfo_UserToken		@"userToken"
#define kAmazonS3ActivationInfo_AccessKeyID		@"accessKeyID"
#define kAmazonS3ActivationInfo_SecretAccessKey	@"secretAccessKey"

@class FileTransferController;

@protocol FileTransferController
@required
- (BOOL) downloadFileFromPath:(NSString*)remotePath toStream:(NSOutputStream*)stream;
- (BOOL) uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream; //Overwrites any pre-existing file - "length" may be 0 if unknown
@optional
- (NSDictionary*) contentsOfDirectoryAtPath:(NSString*)remotePath; //Returns nil if directory does not exist - NSDictionary of NSDictionary with NSFile type keys (at least NSFileType, NSFileModificationDate and NSFileSize are defined)
- (BOOL) createDirectoryAtPath:(NSString*)remotePath; //Fails if directory already exists
- (BOOL) movePath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath; //Overwrites any pre-existing file
- (BOOL) copyPath:(NSString*)fromRemotePath toPath:(NSString*)toRemotePath; //Overwrites any pre-existing file
- (BOOL) deleteFileAtPath:(NSString*)remotePath; //Does not fail if file does not exist
- (BOOL) deleteDirectoryAtPath:(NSString*)remotePath; //Does not fail if directory does not exist, but fails if it is not empty
- (BOOL) deleteDirectoryRecursivelyAtPath:(NSString*)remotePath; //Does not fail if directory does not exist or is not empty
@end

@protocol FileTransferControllerDelegate <NSObject>
@optional
- (void) fileTransferControllerDidStart:(FileTransferController*)controller;
- (void) fileTransferControllerDidUpdateProgress:(FileTransferController*)controller;
- (void) fileTransferControllerDidSucceed:(FileTransferController*)controller;
- (void) fileTransferControllerDidFail:(FileTransferController*)controller withError:(NSError*)error;
- (BOOL) fileTransferControllerShouldAbort:(FileTransferController*)controller;
@end

/* Abstract class: do not instantiate directly */
@interface FileTransferController : NSObject <FileTransferController>
{
@private
	NSURL*								_baseURL;
	id<FileTransferControllerDelegate>	_delegate;
	NSUInteger							_currentLength,
										_maxLength;
	BOOL								_digestComputation;
	NSUInteger							_totalSize;
	void*								_digestContext;
	unsigned char						_digestBuffer[16];
	NSString*							_encryptionPassword;
	void*								_encryptionContext;
	void*								_encryptionBufferBytes;
	NSUInteger							_encryptionBufferSize;
	NSUInteger							_maxUploadSpeed,
										_maxDownloadSpeed;
	BOOL								_fileTransfer;
	double								_maxSpeed;
}
+ (FileTransferController*) fileTransferControllerWithURL:(NSURL*)url;
+ (BOOL) hasAtomicUploads; //Means that a file that failed mid-upload won't appear on the server (e.g. WebDAV)

+ (NSUInteger) globalMaximumDownloadSpeed;
+ (void) setGlobalMaximumDownloadSpeed:(NSUInteger)speed;
+ (NSUInteger) globalMaximumUploadSpeed;
+ (void) setGlobalMaximumUploadSpeed:(NSUInteger)speed;

- (id) initWithHost:(NSString*)host port:(UInt16)port username:(NSString*)username password:(NSString*)password basePath:(NSString*)basePath; //Pass nil or 0 when not needed
- (id) initWithBaseURL:(NSURL*)url;

@property(nonatomic, readonly) NSURL* baseURL;
@property(nonatomic, assign) id<FileTransferControllerDelegate> delegate;
@property(nonatomic, readonly) NSUInteger transferSize; //0 if not defined
@property(nonatomic, readonly) float transferProgress; //In [0,1] range or NAN if not defined

@property(nonatomic, readonly) NSUInteger lastTransferSize;
@property(nonatomic, readonly) NSData* lastTransferDigestData; //MD5 bytes

@property(nonatomic) BOOL digestComputation; //Enables on-the-fly MD5 digest computation for file uploads / downloads
@property(nonatomic, copy) NSString* encryptionPassword; //Enables on-the-fly AES-256 encryption / decryption for file uploads / downloads if not nil (use 'openssl aes-256-cbc -d -k PASSWORD -nosalt -in IN_FILE -out OUT_FILE' to decrypt an uploaded file)

@property(nonatomic) NSUInteger maximumDownloadSpeed; //In bytes per second
@property(nonatomic) NSUInteger maximumUploadSpeed; //In bytes per second

- (NSString*) absolutePathForRemotePath:(NSString*)path;
- (NSURL*) absoluteURLForRemotePath:(NSString*)path; //Returned URL does not contain user or password
- (NSURL*) fullAbsoluteURLForRemotePath:(NSString*)path;
@end

@interface FileTransferController (Extensions)
- (BOOL) uploadFileToPath:(NSString*)remotePath fromStream:(NSInputStream*)stream length:(NSUInteger)length; //Pass 0 if length is unknown 
- (BOOL) downloadFileFromPathToNull:(NSString*)remotePath; //Downloaded data is discarded

- (BOOL) downloadFileFromPath:(NSString*)remotePath toPath:(NSString*)localPath; //Overwrites any pre-existing file
- (BOOL) uploadFileFromPath:(NSString*)localPath toPath:(NSString*)remotePath; //Overwrites any pre-existing file

- (NSData*) downloadFileFromPathToData:(NSString*)remotePath;
- (BOOL) uploadFileFromData:(NSData*)data toPath:(NSString*)remotePath; //Overwrites any pre-existing file

- (NSInteger) downloadFileFromPath:(NSString*)remotePath toBuffer:(void*)buffer capacity:(NSUInteger)capacity; //Return -1 on error
- (BOOL) uploadFileFromBytes:(const void*)buffer length:(NSUInteger)length toPath:(NSString*)remotePath; //Overwrites any pre-existing file
@end

/* Abstract class: do not instantiate directly */
@interface StreamTransferController : FileTransferController
{
@private
	NSInteger							_transferLength,
										_transferOffset;
	unsigned char*						_streamBuffer;
	CFTypeRef							_activeStream;
	id									_dataStream;
	id									_userInfo;
	id									_result;
}
@end

/* Supports everything except -deleteDirectoryAtPath: */
@interface LocalTransferController : StreamTransferController
@end

@interface FileTransferController (LocalTransferController)
@property(nonatomic, readonly, getter=isLocal) BOOL local;
@end

/* Abstract class: do not instantiate directly */
@interface RemoteTransferController : LocalTransferController
{
@private
	FSVolumeRefNum						_volumeRefNum;
	NSString*							_basePath;
}
@end

/* Supports everything except -deleteDirectoryAtPath: */
@interface AFPTransferController : RemoteTransferController
@end

/* Supports everything except -deleteDirectoryAtPath: */
@interface SMBTransferController : RemoteTransferController
@end

/* Only supports downloads and uploads */
@interface HTTPTransferController : StreamTransferController
{
@private
	CFHTTPMessageRef					_responseHeaders;
	BOOL								_disableSSLCertificates;
}
@property(nonatomic, getter=isSSLCertificateValidationDisabled) BOOL SSLCertificateValidationDisabled;
@end

/* Same as HTTPTransferController */
@interface SecureHTTPTransferController : HTTPTransferController
@end

/* Supports everything except -deleteDirectoryAtPath: */
@interface WebDAVTransferController : HTTPTransferController
@end

@interface WebDAVTransferController (iDisk)
- (id) initWithIDiskForLocalUser:(NSString*)basePath;
- (id) initWithIDiskForUser:(NSString*)username basePath:(NSString*)basePath;
- (id) initWithIDiskForUser:(NSString*)username password:(NSString*)password basePath:(NSString*)basePath; //If username is nil, current user is assumed and if password is nil, it is retrieved from the Keychain
@end

/* Same as WebDAVTransferController */
@interface SecureWebDAVTransferController : WebDAVTransferController
@end

/* Supports everything except -movePath:toPath: and -deleteDirectoryAtPath: (the first path component is the bucket and can be nil to operate on the bucket list itself and paths with depth > 2 are not supported) */
/* Contrary to the FileTransferController conventions, deleting non-existent directories returns NO instead of YES and creating an already existing directory returns YES instead of NO (unless the owner differs) */
@interface AmazonS3TransferController : HTTPTransferController
{
@private
	NSString*							_productToken;
	NSString*							_userToken;
	NSString*							_newBucketLocation;
}
+ (NSDictionary*) activateDesktopProduct:(NSString*)productToken activationKey:(NSString*)activationKey expirationInterval:(NSTimeInterval)expirationInterval error:(NSError**)error; //Returns kAmazonS3ActivationInfo_XXX keys
- (id) initWithAccessKeyID:(NSString*)accessKeyID secretAccessKey:(NSString*)secretAccessKey bucket:(NSString*)bucket;
@property(nonatomic, copy) NSString* productToken; //Must start with "{ProductToken}"
@property(nonatomic, copy) NSString* userToken; //Must start with "{UserToken}"
@property(nonatomic, copy) NSString* newBucketLocation; //One of kAmazonS3BucketLocation_XXX or nil for default
@end

/* Same as AmazonS3TransferController */
@interface SecureAmazonS3TransferController : AmazonS3TransferController
@end

/* Supports everything except copy - Always use passive mode */
/* Contrary to the FileTransferController conventions, deleting non-existent files or directories returns NO instead of YES */
@interface FTPTransferController : FileTransferController
{
@private
	void*								_handle;
	NSStringEncoding					_stringEncoding;
	BOOL								_attemptTLSOrSSL;
	id									_transcript;
}
@property(nonatomic) NSStringEncoding stringEncoding; //ISO Latin 1 by default
@property(nonatomic) BOOL attemptTLSOrSSL; //NO by default
@end

/* Supports everything except copy - Always use passive mode */
@interface FTPSTransferController : FTPTransferController
@end

/* Supports everything except copy */
@interface SFTPTransferController : FileTransferController
{
@private
	CFSocketRef							_socket;
	void*								_session;
	void*								_sftp;
}
@end
