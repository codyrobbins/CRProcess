@interface CRProcess : NSObject

@property (readonly) NSNumber *id;
@property (readonly) NSString *executablePath;
@property (readonly) NSArray *arguments;
@property (readonly) NSDictionary *environmentVariables;

+ (NSArray *)processes;

@end