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

@interface NSData (Encryption)
+ (NSData*) md5DigestWithBytes:(const void*)bytes length:(NSUInteger)length;
+ (NSData*) sha1DigestWithBytes:(const void*)bytes length:(NSUInteger)length;

- (NSData*) md5Digest;
- (NSData*) sha1Digest;
- (NSData*) sha1HMacWithKey:(NSString*)key;

- (NSData*) encryptBlowfishWithPassword:(NSString*)password;
- (NSData*) decryptBlowfishWithPassword:(NSString*)password;
- (NSData*) encryptAES128WithPassword:(NSString*)password;
- (NSData*) decryptAES128WithPassword:(NSString*)password;
- (NSData*) encryptAES256WithPassword:(NSString*)password;
- (NSData*) decryptAES256WithPassword:(NSString*)password;

- (NSString*) encodeBase64;
@end

@interface NSString (Encryption)
- (NSData*) decodeBase64;
@end
