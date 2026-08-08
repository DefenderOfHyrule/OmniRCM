#import "MainViewController.h"
#import "RCMDeviceWatcher.h"
#import "RCMInjector.h"
#import "PayloadManager.h"

@interface MainViewController (Icons)
+ (UIImage *)rcmIconNamed:(NSString *)name pointSize:(CGFloat)pointSize;
+ (void)drawTrashIconInContext:(CGContextRef)ctx;
+ (void)drawPencilIconInContext:(CGContextRef)ctx;
+ (void)drawMoonIconInContext:(CGContextRef)ctx;
+ (void)drawSunIconInContext:(CGContextRef)ctx;
+ (void)drawListIconInContext:(CGContextRef)ctx;
@end

static inline UIColor *NXColorHex(NSUInteger hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                            green:((hex >> 8) & 0xFF) / 255.0
                             blue:(hex & 0xFF) / 255.0
                            alpha:1.0];
}

#define kColourPrimary              NXColorHex(0x006494)
#define kColourSecondaryContainer   NXColorHex(0xCDE7FF)
#define kColourOnSecondaryContainer NXColorHex(0x051E2C)
#define kColourSuccess              NXColorHex(0x4CAF50)
#define kColourPatchedV1            NXColorHex(0xFFC107)
#define kColourPatchedV2            NXColorHex(0xF44336)
#define kColourError                NXColorHex(0xF44336)
#define kColourDisconnectedDot      NXColorHex(0x607D8B)

static NSString *const kPrefDarkMode   = @"dark_mode";
static NSString *const kPrefAutoInject = @"auto_inject";

typedef NS_ENUM(NSInteger, PillButtonStyle) {
    PillButtonStyleTonal,
    PillButtonStyleOutlined,
};

#pragma mark - PayloadCell

@interface PayloadCell : UITableViewCell
@property (nonatomic, strong) UIView   *radioOuter;
@property (nonatomic, strong) UIView   *radioInner;
@property (nonatomic, strong) UILabel  *nameLabel;
@property (nonatomic, strong) UILabel  *versionLabel;
@property (nonatomic, strong) UIButton *renameButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, copy) void (^onRename)(void);
@property (nonatomic, copy) void (^onDelete)(void);
- (void)configureWithPayload:(RCMPayload *)payload
                     selected:(BOOL)selected
                    onSurface:(UIColor *)onSurface
             onSurfaceVariant:(UIColor *)onSurfaceVariant
                       accent:(UIColor *)accent;
@end

@implementation PayloadCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;

        self.radioOuter = [[UIView alloc] init];
        self.radioOuter.translatesAutoresizingMaskIntoConstraints = NO;
        self.radioOuter.layer.cornerRadius = 9;
        self.radioOuter.layer.borderWidth = 1.5;
        [self.radioOuter.widthAnchor constraintEqualToConstant:18].active = YES;
        [self.radioOuter.heightAnchor constraintEqualToConstant:18].active = YES;

        self.radioInner = [[UIView alloc] init];
        self.radioInner.translatesAutoresizingMaskIntoConstraints = NO;
        self.radioInner.layer.cornerRadius = 4.5;
        [self.radioOuter addSubview:self.radioInner];
        [NSLayoutConstraint activateConstraints:@[
            [self.radioInner.centerXAnchor constraintEqualToAnchor:self.radioOuter.centerXAnchor],
            [self.radioInner.centerYAnchor constraintEqualToAnchor:self.radioOuter.centerYAnchor],
            [self.radioInner.widthAnchor constraintEqualToConstant:9],
            [self.radioInner.heightAnchor constraintEqualToConstant:9],
        ]];

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];

        self.versionLabel = [[UILabel alloc] init];
        self.versionLabel.font = [UIFont systemFontOfSize:12];

        UIStackView *textStack = [[UIStackView alloc] init];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 1;
        [textStack addArrangedSubview:self.nameLabel];
        [textStack addArrangedSubview:self.versionLabel];

        self.renameButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.renameButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.renameButton.widthAnchor constraintEqualToConstant:32].active = YES;
        [self.renameButton.heightAnchor constraintEqualToConstant:32].active = YES;
        [self.renameButton setImage:[MainViewController rcmIconNamed:@"pencil" pointSize:16] forState:UIControlStateNormal];
        [self.renameButton addTarget:self action:@selector(renameTapped) forControlEvents:UIControlEventTouchUpInside];
        self.renameButton.hidden = YES;

        self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.deleteButton.widthAnchor constraintEqualToConstant:32].active = YES;
        [self.deleteButton.heightAnchor constraintEqualToConstant:32].active = YES;
        [self.deleteButton setImage:[MainViewController rcmIconNamed:@"trash" pointSize:18] forState:UIControlStateNormal];
        [self.deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        self.deleteButton.hidden = YES;

        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 10;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [row addArrangedSubview:self.radioOuter];
        [row addArrangedSubview:textStack];
        [row addArrangedSubview:self.renameButton];
        [row addArrangedSubview:self.deleteButton];

        [self.contentView addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:7],
            [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-7],
            [row.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4],
            [row.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)renameTapped {
    if (self.onRename) self.onRename();
}

- (void)deleteTapped {
    if (self.onDelete) self.onDelete();
}

- (void)configureWithPayload:(RCMPayload *)payload
                     selected:(BOOL)selected
                    onSurface:(UIColor *)onSurface
             onSurfaceVariant:(UIColor *)onSurfaceVariant
                       accent:(UIColor *)accent {
    self.nameLabel.text = payload.name;
    self.nameLabel.textColor = onSurface;
    self.versionLabel.textColor = onSurfaceVariant;

    if (payload.isCustom) {
        self.versionLabel.text = @"custom";
        self.versionLabel.hidden = NO;
    } else if (payload.version) {
        self.versionLabel.text = [NSString stringWithFormat:@"v%@", payload.version];
        self.versionLabel.hidden = NO;
    } else {
        self.versionLabel.hidden = YES;
    }

    self.radioOuter.layer.borderColor = (selected ? accent : onSurfaceVariant).CGColor;
    self.radioInner.backgroundColor = selected ? accent : UIColor.clearColor;

    self.renameButton.hidden = !payload.isCustom;
    self.renameButton.tintColor = onSurfaceVariant;

    self.deleteButton.hidden = !payload.isCustom;
    self.deleteButton.tintColor = kColourError;
}

@end

#pragma mark - MainViewController

@interface MainViewController () <RCMDeviceWatcherDelegate, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) RCMDeviceWatcher *watcher;
@property (nonatomic, assign) NXUSBDeviceInterface **connectedDevice;
@property (nonatomic, assign, getter=isInjecting) BOOL injecting;

@property (nonatomic, assign) RCMResultType lastResultType;
@property (nonatomic, assign) BOOL hasLastResult;

@property (nonatomic, strong) NSArray<RCMPayload *> *payloads;
@property (nonatomic, strong) NSArray<RCMPayload *> *remotePayloads;
@property (nonatomic, strong) NSArray<RCMPayload *> *customPayloads;
@property (nonatomic, strong, nullable) RCMPayload *selectedPayload;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
@property (nonatomic, assign) BOOL autoInject;
@property (nonatomic, assign) BOOL logVisible;
@property (nonatomic, assign) BOOL isDark;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView  *rootStack;

@property (nonatomic, strong) UIView   *headerRow;
@property (nonatomic, strong) UIView   *statusPill;
@property (nonatomic, strong) UIView   *statusDot;
@property (nonatomic, strong) UILabel  *statusLabel;
@property (nonatomic, strong) UIButton *logToggleButton;
@property (nonatomic, strong) UIButton *themeToggleButton;

@property (nonatomic, strong) UILabel  *payloadsSectionLabel;

@property (nonatomic, strong) UIView   *selectedPayloadCard;
@property (nonatomic, strong) UILabel  *selectedPayloadNameLabel;
@property (nonatomic, strong) UILabel  *selectedPayloadSizeLabel;

@property (nonatomic, strong) UIButton *injectButton;
@property (nonatomic, strong) UIButton *fetchButton;
@property (nonatomic, strong) UIButton *addCustomButton;

@property (nonatomic, strong) UILabel  *autoInjectLabel;
@property (nonatomic, strong) UISwitch *autoInjectSwitch;

@property (nonatomic, strong) UIView   *resultPanel;
@property (nonatomic, strong) UILabel  *resultTitleLabel;
@property (nonatomic, strong) UIView   *resultDivider;
@property (nonatomic, strong) UILabel  *resultDetailLabel;
@property (nonatomic, strong) UIButton *resultDismissButton;

@property (nonatomic, strong) UIView     *logSection;
@property (nonatomic, strong) UILabel    *logSectionLabel;
@property (nonatomic, strong) UIButton   *clearLogButton;
@property (nonatomic, strong) UIView     *logCard;
@property (nonatomic, strong) UITextView *logTextView;

@property (nonatomic, strong) UIButton *creditsButton;

@property (nonatomic, strong) UITableView *payloadTable;

@property (nonatomic, strong) UISegmentedControl *tabControl;
@property (nonatomic, strong) UIView *payloadsTabContainer;
@property (nonatomic, strong) UIView *sourcesTabContainer;
@property (nonatomic, strong) UILabel *sourcesSectionLabel;
@property (nonatomic, strong) UIButton *addSourceButton;
@property (nonatomic, strong) UIStackView *sourcesListStack;
@property (nonatomic, strong) UILabel *noSourcesLabel;

- (NSAttributedString *)attributedStringForPatchedV1Detail:(NSString *)plain;

@end

@implementation MainViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.logLines = [NSMutableArray new];
    self.payloads = @[];
    self.remotePayloads = @[];
    self.customPayloads = @[];
    self.autoInject = [[NSUserDefaults standardUserDefaults] boolForKey:kPrefAutoInject];
    self.isDark = [self storedDarkModePreference];
    self.logVisible = NO;

    [self buildUI];
    [self applyTheme];

    self.watcher = [RCMDeviceWatcher new];
    self.watcher.delegate = self;
    [self.watcher start];

    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(reloadPayloads)
        name:PayloadManagerDidUpdateNotification object:nil];
    [self reloadPayloads];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)dealloc {
    [self.watcher stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)storedDarkModePreference {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kPrefDarkMode] == nil) return YES;
    return [defaults boolForKey:kPrefDarkMode];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (self.isDark) return UIStatusBarStyleLightContent;
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){13,0,0}]) {
        return (UIStatusBarStyle)3;
    }
    return UIStatusBarStyleDefault;
}

#pragma mark - Theme colours

- (UIColor *)colourSurface        { return self.isDark ? NXColorHex(0x131A22) : NXColorHex(0xF0F4F8); }
- (UIColor *)colourOnSurface      { return self.isDark ? NXColorHex(0xE1E3E5) : NXColorHex(0x1A2530); }
- (UIColor *)colourSurfaceVariant { return self.isDark ? NXColorHex(0x1E2A34) : NXColorHex(0xD8E4EE); }
- (UIColor *)colourOnSurfaceVariant { return self.isDark ? NXColorHex(0x8FA3B1) : NXColorHex(0x4A6278); }

- (void)applyTheme {
    UIColor *onSurface        = [self colourOnSurface];
    UIColor *surfaceVariant   = [self colourSurfaceVariant];
    UIColor *onSurfaceVariant = [self colourOnSurfaceVariant];

    self.view.backgroundColor = [self colourSurface];

    self.statusPill.backgroundColor = surfaceVariant;
    self.statusLabel.textColor = onSurface;

    self.logToggleButton.backgroundColor = surfaceVariant;
    self.logToggleButton.tintColor = onSurface;
    [self.logToggleButton setTitleColor:onSurface forState:UIControlStateNormal];

    self.themeToggleButton.backgroundColor = surfaceVariant;
    self.themeToggleButton.tintColor = onSurface;
    [self.themeToggleButton setImage:[MainViewController rcmIconNamed:(self.isDark ? @"moon" : @"sun") pointSize:16]
                             forState:UIControlStateNormal];

    self.payloadsSectionLabel.textColor = onSurfaceVariant;
    self.payloadTable.separatorColor = surfaceVariant;

    self.sourcesSectionLabel.textColor = onSurfaceVariant;
    self.noSourcesLabel.textColor = onSurfaceVariant;

    self.selectedPayloadCard.backgroundColor = surfaceVariant;
    self.selectedPayloadNameLabel.textColor = onSurface;
    self.selectedPayloadSizeLabel.textColor = onSurfaceVariant;

    self.autoInjectLabel.textColor = onSurface;

    self.resultPanel.backgroundColor = surfaceVariant;
    self.resultTitleLabel.textColor = onSurface;
    self.resultDivider.backgroundColor = [onSurfaceVariant colorWithAlphaComponent:0.2];
    self.resultDetailLabel.textColor = onSurfaceVariant;
    [self.resultDismissButton setTitleColor:kColourPrimary forState:UIControlStateNormal];

    self.logSectionLabel.textColor = onSurfaceVariant;
    [self.clearLogButton setTitleColor:kColourPrimary forState:UIControlStateNormal];
    self.logCard.backgroundColor = surfaceVariant;
    self.logTextView.textColor = onSurface;

    self.creditsButton.layer.borderColor = onSurfaceVariant.CGColor;
    [self.creditsButton setTitleColor:onSurfaceVariant forState:UIControlStateNormal];

    [self setNeedsStatusBarAppearanceUpdate];
    [self.payloadTable reloadData];
    [self reloadCustomSources];
    [self updatePill];
}

- (void)themeToggleTapped {
    self.isDark = !self.isDark;
    [[NSUserDefaults standardUserDefaults] setBool:self.isDark forKey:kPrefDarkMode];
    [self applyTheme];
}

#pragma mark - UI construction

- (NSLayoutYAxisAnchor *)safeTopAnchor {
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){11,0,0}]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
        return self.view.safeAreaLayoutGuide.topAnchor;
#pragma clang diagnostic pop
    }
    return self.view.topAnchor;
}

- (NSLayoutYAxisAnchor *)safeBottomAnchor {
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){11,0,0}]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
        return self.view.safeAreaLayoutGuide.bottomAnchor;
#pragma clang diagnostic pop
    }
    return self.view.bottomAnchor;
}

- (void)buildUI {
    [self buildHeaderRow];
    [self buildCreditsButton];

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.headerRow.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.creditsButton.topAnchor constant:-4],
    ]];

    self.rootStack = [[UIStackView alloc] init];
    self.rootStack.axis = UILayoutConstraintAxisVertical;
    self.rootStack.spacing = 14;
    self.rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.rootStack.layoutMarginsRelativeArrangement = YES;
    self.rootStack.layoutMargins = UIEdgeInsetsMake(4, 16, 16, 16);
    [self.scrollView addSubview:self.rootStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.rootStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.rootStack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.rootStack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.rootStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.rootStack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];

    [self.rootStack addArrangedSubview:[self buildTabControl]];
    [self.rootStack addArrangedSubview:[self buildPayloadsTabContainer]];
    [self.rootStack addArrangedSubview:[self buildSourcesTabContainer]];
    [self.rootStack addArrangedSubview:[self buildLogSection]];

    self.selectedPayloadCard.hidden = YES;
    self.resultPanel.hidden = YES;
    self.logSection.hidden = YES;
    self.sourcesTabContainer.hidden = YES;
    [self reloadCustomSources];
    [self updateInjectButton];
}

- (UIView *)buildTabControl {
    self.tabControl = [[UISegmentedControl alloc] initWithItems:@[@"Payloads", @"Sources"]];
    self.tabControl.selectedSegmentIndex = 0;
    [self.tabControl addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    return self.tabControl;
}

- (void)tabChanged:(UISegmentedControl *)sender {
    BOOL showSources = sender.selectedSegmentIndex == 1;
    self.payloadsTabContainer.hidden = showSources;
    self.sourcesTabContainer.hidden = !showSources;
}

- (UIView *)buildPayloadsTabContainer {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;

    [stack addArrangedSubview:[self buildPayloadSection]];
    [stack addArrangedSubview:[self buildSelectedPayloadCard]];
    [stack addArrangedSubview:[self buildFetchAddRow]];
    [stack addArrangedSubview:[self buildInjectButton]];
    [stack addArrangedSubview:[self buildAutoInjectRow]];
    [stack addArrangedSubview:[self buildResultPanel]];

    self.payloadsTabContainer = stack;
    return stack;
}

- (UIView *)buildSourcesTabContainer {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;

    UIStackView *headerRow = [[UIStackView alloc] init];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.alignment = UIStackViewAlignmentCenter;

    self.sourcesSectionLabel = [self sectionLabel:@"SOURCES"];
    self.addSourceButton = [self pillButton:@"+ Add" style:PillButtonStyleOutlined];
    [self.addSourceButton addTarget:self action:@selector(addSourceTapped) forControlEvents:UIControlEventTouchUpInside];

    [headerRow addArrangedSubview:self.sourcesSectionLabel];
    [headerRow addArrangedSubview:[[UIView alloc] init]];
    [headerRow addArrangedSubview:self.addSourceButton];

    self.sourcesListStack = [[UIStackView alloc] init];
    self.sourcesListStack.axis = UILayoutConstraintAxisVertical;
    self.sourcesListStack.spacing = 4;

    self.noSourcesLabel = [self label:@"No custom sources added yet." size:12 bold:NO];
    self.noSourcesLabel.numberOfLines = 0;

    [stack addArrangedSubview:headerRow];
    [stack addArrangedSubview:self.sourcesListStack];
    [stack addArrangedSubview:self.noSourcesLabel];

    self.sourcesTabContainer = stack;
    return stack;
}

- (void)buildHeaderRow {
    UIView *headerRow = [[UIView alloc] init];
    headerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:headerRow];
    self.headerRow = headerRow;

    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentFill;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [headerRow addSubview:row];

    self.statusPill = [[UIView alloc] init];
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPill.layer.cornerRadius = 18;
    [self.statusPill.heightAnchor constraintEqualToConstant:36].active = YES;
    [self.statusPill setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *statusInner = [[UIStackView alloc] init];
    statusInner.axis = UILayoutConstraintAxisHorizontal;
    statusInner.spacing = 8;
    statusInner.alignment = UIStackViewAlignmentCenter;
    statusInner.translatesAutoresizingMaskIntoConstraints = NO;
    statusInner.userInteractionEnabled = NO;

    self.statusDot = [[UIView alloc] init];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.layer.cornerRadius = 4;
    [self.statusDot.widthAnchor constraintEqualToConstant:8].active = YES;
    [self.statusDot.heightAnchor constraintEqualToConstant:8].active = YES;

    self.statusLabel = [self label:@"Waiting for RCM device\u2026" size:13 bold:YES];

    [statusInner addArrangedSubview:self.statusDot];
    [statusInner addArrangedSubview:self.statusLabel];
    [self.statusPill addSubview:statusInner];
    [NSLayoutConstraint activateConstraints:@[
        [statusInner.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],
        [statusInner.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor constant:14],
        [statusInner.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusPill.trailingAnchor constant:-14],
    ]];

    self.logToggleButton = [self headerPillButtonWithTitle:@"Log" iconName:@"list"];
    [self.logToggleButton addTarget:self action:@selector(toggleLog:) forControlEvents:UIControlEventTouchUpInside];

    self.themeToggleButton = [self circularIconButtonWithFallbackGlyph:@"\u263D"];
    [self.themeToggleButton addTarget:self action:@selector(themeToggleTapped) forControlEvents:UIControlEventTouchUpInside];

    [row addArrangedSubview:self.statusPill];
    [row addArrangedSubview:self.logToggleButton];
    [row addArrangedSubview:self.themeToggleButton];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:headerRow.topAnchor constant:12],
        [row.bottomAnchor constraintEqualToAnchor:headerRow.bottomAnchor constant:-8],
        [row.leadingAnchor constraintEqualToAnchor:headerRow.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:headerRow.trailingAnchor constant:-16],
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [headerRow.topAnchor constraintEqualToAnchor:[self safeTopAnchor]],
        [headerRow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [headerRow.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (UIButton *)headerPillButtonWithTitle:(NSString *)title iconName:(NSString *)iconName {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    btn.layer.cornerRadius = 18;
    [btn.heightAnchor constraintEqualToConstant:36].active = YES;

    [btn setImage:[MainViewController rcmIconNamed:iconName pointSize:14] forState:UIControlStateNormal];
    [btn setTitle:[NSString stringWithFormat:@" %@", title] forState:UIControlStateNormal];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    btn.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
#pragma clang diagnostic pop
    return btn;
}

- (UIButton *)circularIconButtonWithFallbackGlyph:(NSString *)glyph {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn.widthAnchor constraintEqualToConstant:36].active = YES;
    [btn.heightAnchor constraintEqualToConstant:36].active = YES;
    btn.layer.cornerRadius = 18;
    btn.layer.masksToBounds = YES;
    return btn;
}

- (UIView *)buildPayloadSection {
    UIView *container = [[UIView alloc] init];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];

    self.payloadsSectionLabel = [self sectionLabel:@"PAYLOADS"];

    self.payloadTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.payloadTable.backgroundColor = UIColor.clearColor;
    self.payloadTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.payloadTable.dataSource = self;
    self.payloadTable.delegate = self;
    self.payloadTable.scrollEnabled = NO;
    self.payloadTable.rowHeight = UITableViewAutomaticDimension;
    self.payloadTable.estimatedRowHeight = 52;
    self.payloadTable.translatesAutoresizingMaskIntoConstraints = NO;
    [self.payloadTable registerClass:[PayloadCell class] forCellReuseIdentifier:@"PayloadCell"];
    [self.payloadTable.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;

    [stack addArrangedSubview:self.payloadsSectionLabel];
    [stack addArrangedSubview:self.payloadTable];
    return container;
}

- (UIView *)buildSelectedPayloadCard {
    self.selectedPayloadCard = [[UIView alloc] init];
    self.selectedPayloadCard.layer.cornerRadius = 8;

    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self.selectedPayloadCard addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:self.selectedPayloadCard.topAnchor constant:10],
        [row.bottomAnchor constraintEqualToAnchor:self.selectedPayloadCard.bottomAnchor constant:-10],
        [row.leadingAnchor constraintEqualToAnchor:self.selectedPayloadCard.leadingAnchor constant:10],
        [row.trailingAnchor constraintEqualToAnchor:self.selectedPayloadCard.trailingAnchor constant:-10],
    ]];

    self.selectedPayloadNameLabel = [self label:@"" size:13 bold:YES];
    self.selectedPayloadSizeLabel = [self label:@"" size:11 bold:NO];

    [row addArrangedSubview:self.selectedPayloadNameLabel];
    [row addArrangedSubview:[[UIView alloc] init]];
    [row addArrangedSubview:self.selectedPayloadSizeLabel];
    return self.selectedPayloadCard;
}

- (UIView *)buildFetchAddRow {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 8;

    self.fetchButton = [self pillButton:@"Fetch payloads" style:PillButtonStyleTonal];
    [self.fetchButton addTarget:self action:@selector(fetchTapped) forControlEvents:UIControlEventTouchUpInside];
    self.addCustomButton = [self pillButton:@"Add custom" style:PillButtonStyleOutlined];
    [self.addCustomButton addTarget:self action:@selector(addCustomTapped) forControlEvents:UIControlEventTouchUpInside];

    [row addArrangedSubview:self.fetchButton];
    [row addArrangedSubview:self.addCustomButton];
    return row;
}

- (UIView *)buildInjectButton {
    self.injectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.injectButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.injectButton setTitle:@"Inject" forState:UIControlStateNormal];
    [self.injectButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.injectButton setTitleColor:[UIColor.whiteColor colorWithAlphaComponent:0.4]
                            forState:UIControlStateDisabled];
    self.injectButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.injectButton.backgroundColor = kColourPrimary;
    self.injectButton.layer.cornerRadius = 10;
    [self.injectButton.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.injectButton addTarget:self action:@selector(injectTapped) forControlEvents:UIControlEventTouchUpInside];
    return self.injectButton;
}

- (UIView *)buildAutoInjectRow {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;

    self.autoInjectLabel = [self label:@"Auto-inject on device connect" size:14 bold:NO];
    self.autoInjectSwitch = [[UISwitch alloc] init];
    self.autoInjectSwitch.on = self.autoInject;
    self.autoInjectSwitch.onTintColor = kColourPrimary;
    [self.autoInjectSwitch addTarget:self action:@selector(autoInjectChanged:) forControlEvents:UIControlEventValueChanged];

    [row addArrangedSubview:self.autoInjectLabel];
    [row addArrangedSubview:[[UIView alloc] init]];
    [row addArrangedSubview:self.autoInjectSwitch];
    return row;
}

- (UIView *)buildResultPanel {
    self.resultPanel = [[UIView alloc] init];
    self.resultPanel.layer.cornerRadius = 16;
    self.resultPanel.layer.borderWidth = 2.5;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resultPanel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.resultPanel.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:self.resultPanel.bottomAnchor constant:-14],
        [stack.leadingAnchor constraintEqualToAnchor:self.resultPanel.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:self.resultPanel.trailingAnchor constant:-14],
    ]];

    self.resultTitleLabel = [self label:@"" size:16 bold:YES];

    self.resultDivider = [[UIView alloc] init];
    [self.resultDivider.heightAnchor constraintEqualToConstant:1].active = YES;

    self.resultDetailLabel = [self label:@"" size:13 bold:NO];
    self.resultDetailLabel.numberOfLines = 0;

    self.resultDismissButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resultDismissButton setTitle:@"Dismiss" forState:UIControlStateNormal];
    self.resultDismissButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [self.resultDismissButton addTarget:self action:@selector(dismissResult) forControlEvents:UIControlEventTouchUpInside];

    [stack addArrangedSubview:self.resultTitleLabel];
    [stack addArrangedSubview:self.resultDivider];
    [stack addArrangedSubview:self.resultDetailLabel];
    [stack addArrangedSubview:self.resultDismissButton];
    return self.resultPanel;
}

- (UIView *)buildLogSection {
    self.logSection = [[UIView alloc] init];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.logSection addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.logSection.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.logSection.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.logSection.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.logSection.trailingAnchor],
    ]];

    UIStackView *header = [[UIStackView alloc] init];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;

    self.logSectionLabel = [self sectionLabel:@"LOG"];
    self.clearLogButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearLogButton setTitle:@"Clear" forState:UIControlStateNormal];
    [self.clearLogButton addTarget:self action:@selector(clearLog) forControlEvents:UIControlEventTouchUpInside];

    [header addArrangedSubview:self.logSectionLabel];
    [header addArrangedSubview:[[UIView alloc] init]];
    [header addArrangedSubview:self.clearLogButton];

    self.logCard = [[UIView alloc] init];
    self.logCard.layer.cornerRadius = 8;

    self.logTextView = [[UITextView alloc] init];
    self.logTextView.backgroundColor = UIColor.clearColor;
    self.logTextView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.logTextView.editable = NO;
    self.logTextView.scrollEnabled = NO;
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.logCard addSubview:self.logTextView];
    [NSLayoutConstraint activateConstraints:@[
        [self.logTextView.topAnchor constraintEqualToAnchor:self.logCard.topAnchor constant:10],
        [self.logTextView.bottomAnchor constraintEqualToAnchor:self.logCard.bottomAnchor constant:-10],
        [self.logTextView.leadingAnchor constraintEqualToAnchor:self.logCard.leadingAnchor constant:10],
        [self.logTextView.trailingAnchor constraintEqualToAnchor:self.logCard.trailingAnchor constant:-10],
    ]];

    [stack addArrangedSubview:header];
    [stack addArrangedSubview:self.logCard];
    return self.logSection;
}

- (void)buildCreditsButton {
    self.creditsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.creditsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.creditsButton setTitle:@"Credits" forState:UIControlStateNormal];
    self.creditsButton.titleLabel.font = [UIFont systemFontOfSize:11];
    self.creditsButton.layer.cornerRadius = 6;
    self.creditsButton.layer.borderWidth = 1;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.creditsButton.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
#pragma clang diagnostic pop
    [self.creditsButton addTarget:self action:@selector(showCredits) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.creditsButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.creditsButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.creditsButton.bottomAnchor constraintEqualToAnchor:[self safeBottomAnchor] constant:-8],
    ]];
}

#pragma mark - Drawn icons

+ (UIImage *)rcmIconNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize size = CGSizeMake(pointSize, pointSize);
    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextScaleCTM(ctx, pointSize / 24.0, pointSize / 24.0);
    CGContextSetLineWidth(ctx, 1.8);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextSetStrokeColorWithColor(ctx, [UIColor blackColor].CGColor);
    CGContextSetFillColorWithColor(ctx, [UIColor blackColor].CGColor);

    if ([name isEqualToString:@"trash"]) {
        [self drawTrashIconInContext:ctx];
    } else if ([name isEqualToString:@"pencil"]) {
        [self drawPencilIconInContext:ctx];
    } else if ([name isEqualToString:@"moon"]) {
        [self drawMoonIconInContext:ctx];
    } else if ([name isEqualToString:@"sun"]) {
        [self drawSunIconInContext:ctx];
    } else if ([name isEqualToString:@"list"]) {
        [self drawListIconInContext:ctx];
    }

    CGContextRestoreGState(ctx);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

+ (void)drawTrashIconInContext:(CGContextRef)ctx {
    UIBezierPath *lid = [UIBezierPath bezierPath];
    [lid moveToPoint:CGPointMake(5, 6)];
    [lid addLineToPoint:CGPointMake(19, 6)];
    [lid stroke];

    UIBezierPath *handle = [UIBezierPath bezierPath];
    [handle moveToPoint:CGPointMake(9, 6)];
    [handle addLineToPoint:CGPointMake(9.5, 3.5)];
    [handle addLineToPoint:CGPointMake(14.5, 3.5)];
    [handle addLineToPoint:CGPointMake(15, 6)];
    [handle stroke];

    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(6, 7, 12, 13) cornerRadius:1.5];
    [body stroke];

    for (CGFloat x = 9; x <= 15; x += 3) {
        UIBezierPath *strike = [UIBezierPath bezierPath];
        [strike moveToPoint:CGPointMake(x, 9.5)];
        [strike addLineToPoint:CGPointMake(x, 17)];
        [strike stroke];
    }
}

+ (void)drawPencilIconInContext:(CGContextRef)ctx {
    UIBezierPath *body = [UIBezierPath bezierPath];
    [body moveToPoint:CGPointMake(4, 20)];
    [body addLineToPoint:CGPointMake(5, 15.5)];
    [body addLineToPoint:CGPointMake(15.5, 5)];
    [body addLineToPoint:CGPointMake(19, 8.5)];
    [body addLineToPoint:CGPointMake(8.5, 19)];
    [body addLineToPoint:CGPointMake(4, 20)];
    [body closePath];
    [body stroke];

    UIBezierPath *tipLine = [UIBezierPath bezierPath];
    [tipLine moveToPoint:CGPointMake(13, 7)];
    [tipLine addLineToPoint:CGPointMake(17, 11)];
    [tipLine stroke];
}

+ (void)drawMoonIconInContext:(CGContextRef)ctx {
    UIBezierPath *disc = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 4, 16, 16)];
    [disc fill];

    CGContextSaveGState(ctx);
    CGContextSetBlendMode(ctx, kCGBlendModeClear);
    UIBezierPath *bite = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(8.5, 1.5, 15, 15)];
    [bite fill];
    CGContextRestoreGState(ctx);
}

+ (void)drawSunIconInContext:(CGContextRef)ctx {
    UIBezierPath *core = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(7, 7, 10, 10)];
    [core fill];

    for (NSInteger i = 0; i < 8; i++) {
        CGFloat angle = i * (M_PI / 4.0);
        CGFloat innerR = 7.5, outerR = 11;
        CGPoint p1 = CGPointMake(12 + innerR * cos(angle), 12 + innerR * sin(angle));
        CGPoint p2 = CGPointMake(12 + outerR * cos(angle), 12 + outerR * sin(angle));
        UIBezierPath *ray = [UIBezierPath bezierPath];
        [ray moveToPoint:p1];
        [ray addLineToPoint:p2];
        [ray stroke];
    }
}

+ (void)drawListIconInContext:(CGContextRef)ctx {
    CGFloat ys[] = {6, 12, 18};
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat y = ys[i];
        UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, y - 1.2, 2.4, 2.4)];
        [dot fill];
        UIBezierPath *line = [UIBezierPath bezierPath];
        [line moveToPoint:CGPointMake(9, y)];
        [line addLineToPoint:CGPointMake(20, y)];
        [line stroke];
    }
}

#pragma mark - Small helpers

- (UILabel *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.textColor = [self colourOnSurface];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    return l;
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.textColor = [self colourOnSurfaceVariant];
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    return l;
}

- (UIButton *)pillButton:(NSString *)title style:(PillButtonStyle)style {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.layer.cornerRadius = 8;
    btn.layer.borderWidth = (style == PillButtonStyleOutlined) ? 1 : 0;
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [btn setTitle:title forState:UIControlStateNormal];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    btn.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
#pragma clang diagnostic pop
    if (style == PillButtonStyleOutlined) {
        btn.backgroundColor = UIColor.clearColor;
        [btn setTitleColor:kColourPrimary forState:UIControlStateNormal];
        btn.layer.borderColor = kColourPrimary.CGColor;
    } else {
        btn.backgroundColor = kColourSecondaryContainer;
        [btn setTitleColor:kColourOnSecondaryContainer forState:UIControlStateNormal];
    }
    return btn;
}

- (void)updateInjectButton {
    BOOL canInject = self.selectedPayload != nil && self.connectedDevice != NULL && !self.isInjecting;
    self.injectButton.enabled = canInject;
    self.injectButton.backgroundColor = canInject ? kColourPrimary : [kColourPrimary colorWithAlphaComponent:0.35];
}

#pragma mark - Payload list

- (void)reloadPayloads {
    NSArray<RCMPayload *> *all = [PayloadManager shared].payloads;
    self.payloads = all;

    NSMutableArray<RCMPayload *> *remote = [NSMutableArray new];
    NSMutableArray<RCMPayload *> *custom = [NSMutableArray new];
    for (RCMPayload *p in all) {
        if (p.isCustom) { [custom addObject:p]; } else { [remote addObject:p]; }
    }
    self.remotePayloads = remote;
    self.customPayloads = custom;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.payloadTable reloadData];

        [self.payloadTable layoutIfNeeded];
        CGFloat h = self.payloadTable.contentSize.height;
        for (NSLayoutConstraint *c in self.payloadTable.constraints) {
            if (c.firstAttribute == NSLayoutAttributeHeight) {
                [self.payloadTable removeConstraint:c];
            }
        }
        [self.payloadTable.heightAnchor constraintEqualToConstant:MAX(h, 44)].active = YES;
        [self updateInjectButton];
    });
}

- (RCMPayload *)payloadAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? self.remotePayloads[indexPath.row] : self.customPayloads[indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.remotePayloads.count : self.customPayloads.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PayloadCell *cell = [tv dequeueReusableCellWithIdentifier:@"PayloadCell" forIndexPath:indexPath];
    RCMPayload *payload = [self payloadAtIndexPath:indexPath];
    BOOL selected = (payload == self.selectedPayload);
    [cell configureWithPayload:payload
                       selected:selected
                      onSurface:[self colourOnSurface]
               onSurfaceVariant:[self colourOnSurfaceVariant]
                         accent:kColourPrimary];
    __weak typeof(self) weakSelf = self;
    cell.onRename = ^{
        [weakSelf presentRenamePayload:payload];
    };
    cell.onDelete = ^{
        [weakSelf confirmDeletePayload:payload];
    };
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    self.selectedPayload = [self payloadAtIndexPath:indexPath];
    [tv reloadData];
    [self showSelectedPayload:self.selectedPayload];
    [self updateInjectButton];
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    if (section == 1 && self.customPayloads.count > 0) return 28;
    return 0.01;
}

- (CGFloat)tableView:(UITableView *)tv estimatedHeightForHeaderInSection:(NSInteger)section {
    return [self tableView:tv heightForHeaderInSection:section];
}

- (nullable UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    if (section == 1 && self.customPayloads.count > 0) {
        UIView *container = [[UIView alloc] init];
        UILabel *lbl = [self sectionLabel:@"CUSTOM"];
        lbl.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:lbl];
        [NSLayoutConstraint activateConstraints:@[
            [lbl.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
            [lbl.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-6],
        ]];
        return container;
    }
    return nil;
}

- (void)showSelectedPayload:(RCMPayload *)payload {
    self.selectedPayloadCard.hidden = NO;
    self.selectedPayloadNameLabel.text = payload.name;
    self.selectedPayloadSizeLabel.text = [NSString stringWithFormat:@"%@ bytes",
        [NSNumberFormatter localizedStringFromNumber:@(payload.fileSize)
                                        numberStyle:NSNumberFormatterDecimalStyle]];
}

- (void)presentRenamePayload:(RCMPayload *)payload {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename payload"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = payload.name;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *newName = [weakAlert.textFields.firstObject.text
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newName.length == 0) {
            [weakSelf appendLog:@"[ERROR] Payload name cannot be empty."];
            return;
        }
        NSError *err = nil;
        RCMPayload *renamed = [[PayloadManager shared] renamePayload:payload newName:newName error:&err];
        if (!renamed) {
            [weakSelf appendLog:[NSString stringWithFormat:@"[ERROR] Could not rename payload: %@",
                err.localizedDescription ?: @"unknown error"]];
            return;
        }
        if (weakSelf.selectedPayload == payload) {
            weakSelf.selectedPayload = renamed;
            [weakSelf showSelectedPayload:renamed];
        }
        [weakSelf appendLog:[NSString stringWithFormat:@"Renamed payload to: %@", renamed.name]];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeletePayload:(RCMPayload *)payload {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete payload"
        message:[NSString stringWithFormat:@"Remove \"%@\" from custom payloads?", payload.name]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[PayloadManager shared] deletePayload:payload];
        if (weakSelf.selectedPayload == payload) {
            weakSelf.selectedPayload = nil;
            weakSelf.selectedPayloadCard.hidden = YES;
        }
        [weakSelf updateInjectButton];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Sources

- (void)reloadCustomSources {
    for (UIView *v in self.sourcesListStack.arrangedSubviews) {
        [self.sourcesListStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray<RCMCustomSource *> *sources = [PayloadManager shared].customSources;
    self.noSourcesLabel.hidden = sources.count > 0;

    for (NSUInteger i = 0; i < sources.count; i++) {
        [self.sourcesListStack addArrangedSubview:[self buildSourceRow:sources[i] index:i]];
    }
}

- (UIView *)buildSourceRow:(RCMCustomSource *)source index:(NSUInteger)index {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;

    UILabel *nameLabel = [self label:source.name size:14 bold:YES];
    UILabel *repoLabel = [self label:source.repo size:12 bold:NO];
    repoLabel.textColor = [self colourOnSurfaceVariant];

    UIStackView *textStack = [[UIStackView alloc] init];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 1;
    [textStack addArrangedSubview:nameLabel];
    [textStack addArrangedSubview:repoLabel];

    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [deleteButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [deleteButton.heightAnchor constraintEqualToConstant:32].active = YES;
    [deleteButton setImage:[MainViewController rcmIconNamed:@"trash" pointSize:16] forState:UIControlStateNormal];
    deleteButton.tintColor = kColourError;
    deleteButton.tag = (NSInteger)index;
    [deleteButton addTarget:self action:@selector(deleteSourceTapped:) forControlEvents:UIControlEventTouchUpInside];

    [row addArrangedSubview:textStack];
    [row addArrangedSubview:deleteButton];
    return row;
}

- (void)deleteSourceTapped:(UIButton *)sender {
    NSArray<RCMCustomSource *> *sources = [PayloadManager shared].customSources;
    if ((NSUInteger)sender.tag >= sources.count) return;
    RCMCustomSource *source = sources[sender.tag];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete source"
        message:[NSString stringWithFormat:@"Remove \"%@\" from custom sources?", source.name]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[PayloadManager shared] removeCustomSourceNamed:source.name];
        if (weakSelf.selectedPayload && !weakSelf.selectedPayload.isCustom &&
            [weakSelf.selectedPayload.name isEqualToString:source.name]) {
            weakSelf.selectedPayload = nil;
            weakSelf.selectedPayloadCard.hidden = YES;
        }
        [weakSelf reloadCustomSources];
        [weakSelf updateInjectButton];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addSourceTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add payload source"
        message:@"Fetch a custom payload from a GitHub repository's latest release."
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Display name";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"owner/repo";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Release asset filename, e.g. hekate_ctcaer_*_Nyx_*.zip";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Not a .zip" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf finishAddSourceWithAlert:weakAlert isZip:NO zipPattern:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"It's a .zip archive" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf presentZipPatternPromptForAlert:weakAlert];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentZipPatternPromptForAlert:(UIAlertController *)sourceAlert {
    UIAlertController *zipAlert = [UIAlertController alertControllerWithTitle:@"Archive contents"
        message:@"Which file inside the archive should be used? Supports * wildcards."
        preferredStyle:UIAlertControllerStyleAlert];
    [zipAlert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = @"*.bin";
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [zipAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakZipAlert = zipAlert;
    [zipAlert addAction:[UIAlertAction actionWithTitle:@"Add source" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *pattern = weakZipAlert.textFields.firstObject.text;
        [weakSelf finishAddSourceWithAlert:sourceAlert isZip:YES zipPattern:pattern];
    }]];
    [self presentViewController:zipAlert animated:YES completion:nil];
}

- (void)finishAddSourceWithAlert:(UIAlertController *)sourceAlert isZip:(BOOL)isZip zipPattern:(nullable NSString *)zipPattern {
    NSArray<UITextField *> *fields = sourceAlert.textFields;
    RCMCustomSource *source = [RCMCustomSource new];
    source.name = fields[0].text ?: @"";
    source.repo = fields[1].text ?: @"";
    source.assetMatch = fields[2].text ?: @"";
    source.isZip = isZip;
    source.zipInnerPattern = zipPattern.length > 0 ? zipPattern : @"*.bin";

    NSString *error = [[PayloadManager shared] addCustomSource:source];
    if (error) {
        [self appendLog:[NSString stringWithFormat:@"[ERROR] Could not add source: %@", error]];
        return;
    }
    [self reloadCustomSources];
    [self appendLog:[NSString stringWithFormat:@"Added source: %@", source.name]];
}

#pragma mark - Log

- (void)appendLog:(NSString *)line {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logLines addObject:line];
        self.logTextView.text = [self.logLines componentsJoinedByString:@"\n"];
        if (self.logVisible) {
            [self scrollToBottom];
        }
    });
}

- (void)scrollToBottom {
    CGPoint bottom = CGPointMake(0, MAX(self.scrollView.contentSize.height
                                       - self.scrollView.bounds.size.height, 0));
    [self.scrollView setContentOffset:bottom animated:YES];
}

- (void)toggleLog:(UIButton *)btn {
    self.logVisible = !self.logVisible;
    self.logSection.hidden = !self.logVisible;
    if (self.logVisible) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scrollToBottom];
        });
    }
}

- (void)clearLog {
    [self.logLines removeAllObjects];
    self.logTextView.text = @"";
}

#pragma mark - Status pill / result

- (void)updatePill {
    if (self.hasLastResult) {
        switch (self.lastResultType) {
            case RCMResultSuccess:
                [self setStatusText:@"Injection successful" dotColour:kColourSuccess];
                break;
            case RCMResultPatchedV1:
                [self setStatusText:@"Patched V1 console" dotColour:kColourPatchedV1];
                break;
            case RCMResultPatchedV2:
                [self setStatusText:@"V2/Mariko console" dotColour:kColourPatchedV2];
                break;
            case RCMResultError:
                [self setStatusText:@"Injection failed" dotColour:kColourError];
                break;
        }
    } else {
        if (self.connectedDevice != NULL) {
            [self setStatusText:@"RCM device connected" dotColour:kColourSuccess];
        } else {
            [self setStatusText:@"Waiting for RCM device\u2026" dotColour:kColourDisconnectedDot];
        }
    }
}

- (void)setStatusText:(NSString *)text dotColour:(UIColor *)dotColour {
    void (^update)(void) = ^{
        self.statusLabel.text = text;
        self.statusDot.backgroundColor = dotColour;
    };
    if ([NSThread isMainThread]) {
        update();
    } else {
        dispatch_async(dispatch_get_main_queue(), update);
    }
}

- (NSAttributedString *)attributedStringForPatchedV1Detail:(NSString *)plain {
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:plain];
    UIFont *base = [UIFont systemFontOfSize:13];
    [s addAttribute:NSFontAttributeName value:base range:NSMakeRange(0, s.length)];

    NSRange noteRange = [plain rangeOfString:@"Note:"];
    if (noteRange.location != NSNotFound) {
        [s addAttribute:NSFontAttributeName
                  value:[UIFont boldSystemFontOfSize:13]
                  range:noteRange];
    }

    NSRange knownRange = [plain rangeOfString:@"known unpatched console"];
    if (knownRange.location != NSNotFound) {
        UIFontDescriptor *fd = [[UIFont boldSystemFontOfSize:13].fontDescriptor
            fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold | UIFontDescriptorTraitItalic];
        [s addAttribute:NSFontAttributeName
                  value:[UIFont fontWithDescriptor:fd size:13]
                  range:knownRange];
    }

    return s;
}

- (void)showResult:(RCMResult *)result {
    NSString *title, *detail;
    UIColor *colour;

    switch (result.type) {
        case RCMResultSuccess:
            title = @"\u2713 Injection successful";
            detail = @"The payload was sent successfully. The Switch should now be booted into the selected payload. You may disconnect the USB cable and continue to follow the guide.";
            colour = kColourSuccess;
            break;
        case RCMResultPatchedV1:
            title = @"\u2717 Patched V1 console";
            detail = @"This console has an updated bootROM and cannot be exploited via RCM.\n\nNote: If you get this result with a known unpatched console, please retry payload injection.\nEnable the log at the top and see if the transfer timed out past 65536; if it did, try a different USB cable.";
            colour = kColourPatchedV1;
            break;
        case RCMResultPatchedV2:
            title = @"\u2717 V2/Mariko console";
            detail = @"This is a Mariko (V2) console. The fusee-gelee exploit does not apply to this hardware revision.";
            colour = kColourPatchedV2;
            break;
        case RCMResultError:
            title = @"\u2717 Injection Failed";
            detail = @"An error occurred during injection. Check the log for details. Make sure the device was freshly put in RCM and the cable is properly connected.";
            colour = kColourError;
            break;
    }

    self.hasLastResult = YES;
    self.lastResultType = result.type;
    [self updatePill];

    self.resultTitleLabel.text = title;
    if (result.type == RCMResultPatchedV1) {
        self.resultDetailLabel.attributedText = [self attributedStringForPatchedV1Detail:detail];
    } else {
        self.resultDetailLabel.text = detail;
    }
    self.resultPanel.layer.borderColor = colour.CGColor;
    self.resultPanel.backgroundColor = [self colourSurfaceVariant];
    self.resultPanel.hidden = NO;
    [self scrollToBottom];
}

- (void)dismissResult {
    self.resultPanel.hidden = YES;
    self.hasLastResult = NO;
    [self updatePill];

    [self.watcher stop];
    [self.watcher start];
}

#pragma mark - Actions

- (void)fetchTapped {
    self.fetchButton.enabled = NO;
    [self appendLog:@"Fetching payloads..."];
    [[PayloadManager shared] fetchAllWithLog:^(NSString *line) {
        [self appendLog:line];
    } completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.fetchButton.enabled = YES;
            [self appendLog:@"Done."];
        });
    }];
}

- (void)addCustomTapped {
    NSArray *docTypes = @[@"public.item", @"public.data"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:docTypes inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){11,0,0}]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
        picker.allowsMultipleSelection = NO;
#pragma clang diagnostic pop
    }
    picker.delegate = (id<UIDocumentPickerDelegate>)self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    if (!url) return;
    [url startAccessingSecurityScopedResource];
    NSError *err = nil;
    RCMPayload *payload = [[PayloadManager shared] addCustomPayloadFromURL:url error:&err];
    [url stopAccessingSecurityScopedResource];
    if (err) {
        [self appendLog:[NSString stringWithFormat:@"[ERROR] Could not import payload: %@", err.localizedDescription]];
    } else if (payload) {
        [self appendLog:[NSString stringWithFormat:@"Added custom payload: %@", payload.name]];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self documentPicker:controller didPickDocumentAtURL:urls.firstObject];
}

- (void)autoInjectChanged:(UISwitch *)sw {
    self.autoInject = sw.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:kPrefAutoInject];
}

- (void)showCredits {
    NSString *body = @"Payload injector for the Nintendo Switch.\n\nOmniRCM iOS is based on OmniRCM for Android by DefenderOfHyrule.\nInjection logic adapted from NXBoot by mologie.\nFuse\u0301e Gele\u0301e exploit by ReSwitched.";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"About OmniRCM"
        message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"GitHub" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self openGitHub];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/DefenderOfHyrule"]
                                       options:@{} completionHandler:nil];
}

#pragma mark - Injection

- (void)injectTapped {
    if (!self.selectedPayload || self.connectedDevice == NULL || self.isInjecting) return;
    [self runInjection];
}

- (void)runInjection {
    self.injecting = YES;
    self.resultPanel.hidden = YES;
    [self updateInjectButton];

    RCMPayload *payload = self.selectedPayload;
    NXUSBDeviceInterface **device = self.connectedDevice;
    NSData *intermezzo = [PayloadManager shared].intermezzoData;

    if (!intermezzo) {
        [self appendLog:@"[ERROR] intermezzo.bin not found in app bundle."];
        self.injecting = NO;
        [self updateInjectButton];
        return;
    }

    NSData *payloadData = [NSData dataWithContentsOfURL:payload.fileURL];
    if (!payloadData) {
        [self appendLog:@"[ERROR] Could not read payload file."];
        self.injecting = NO;
        [self updateInjectButton];
        return;
    }

    [self appendLog:[NSString stringWithFormat:@"Injecting %@...", payload.name]];
    [self appendLog:[NSString stringWithFormat:@"Loaded: %@ (%@ bytes)",
        payload.fileURL.lastPathComponent,
        [NSNumberFormatter localizedStringFromNumber:@(payloadData.length)
                                        numberStyle:NSNumberFormatterDecimalStyle]]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RCMResult *result = [RCMInjector injectPayload:payloadData
                                            intermezzo:intermezzo
                                                device:device
                                              logBlock:^(NSString *line) {
            [self appendLog:line];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.connectedDevice = NULL;
            self.injecting = NO;
            [self updateInjectButton];

            switch (result.type) {
                case RCMResultSuccess:
                    [self appendLog:[NSString stringWithFormat:@"\u2713 Injection successful, device ID: %@", result.deviceId]];
                    break;
                case RCMResultPatchedV1:
                    [self appendLog:@"\u2717 Console is patched (V1 patched console), this console is not exploitable via RCM."];
                    break;
                case RCMResultPatchedV2:
                    [self appendLog:@"\u2717 Console is not exploitable via RCM (V2/Mariko console)."];
                    break;
                case RCMResultError:
                    [self appendLog:[NSString stringWithFormat:@"\u2717 %@", result.errorMessage]];
                    break;
            }

            [self showResult:result];

            [self.watcher stop];
            [self.watcher start];
        });
    });
}

#pragma mark - RCMDeviceWatcherDelegate

- (void)deviceWatcher:(RCMDeviceWatcher *)watcher deviceConnected:(NXUSBDeviceInterface **)device {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connectedDevice = device;
        [self updatePill];
        [self updateInjectButton];
        if (self.autoInject && self.selectedPayload) {
            [self runInjection];
        }
    });
}

- (void)deviceWatcher:(RCMDeviceWatcher *)watcher deviceDisconnected:(NXUSBDeviceInterface **)device {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connectedDevice = NULL;
        [self updatePill];
        [self updateInjectButton];
        [self.watcher stop];
        [self.watcher start];
    });
}

- (void)deviceWatcher:(RCMDeviceWatcher *)watcher error:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self appendLog:[NSString stringWithFormat:@"[USB ERROR] %@", message]];
        [self setStatusText:@"USB error" dotColour:kColourError];
    });
}

- (void)deviceWatcher:(RCMDeviceWatcher *)watcher diagnostic:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self appendLog:[NSString stringWithFormat:@"[USB] %@", message]];
    });
}

@end