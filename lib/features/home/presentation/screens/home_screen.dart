import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/features/home/presentation/bloc/home_bloc.dart';
import 'package:nomowear/features/categories/presentation/screens/categories_screen.dart';
import 'package:nomowear/features/home/presentation/screens/subscription_tab_widget.dart';
import 'package:nomowear/features/subscriptions/presentation/bloc/subscription_bloc.dart';
import 'package:nomowear/features/subscriptions/data/subscription_garment_balance.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/features/auth/data/models/customer.dart';
import 'package:nomowear/features/banners/data/banner_cache.dart';
import 'package:nomowear/features/banners/data/banner_repository.dart';
import 'package:nomowear/features/banners/data/models/promo_banner.dart';
import 'package:nomowear/features/categories/data/category_cache.dart';
import 'package:nomowear/features/categories/data/category_repository.dart';
import 'package:nomowear/features/categories/data/models/wardrobe_category.dart';
import 'package:nomowear/features/profile/data/profile_cache.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';
import 'package:nomowear/features/profile/presentation/screens/profile_screen.dart';
import 'package:nomowear/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:nomowear/features/notifications/data/notifications_repository.dart';
import 'package:nomowear/features/cart/presentation/screens/cart_screen.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/checkout/presentation/utils/wardrobe_booking_flow.dart';
import 'custom_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  final int initialTabIndex;
  final bool refreshHomeOnEnter;
  final String refreshSource;

  const HomeScreen({
    Key? key,
    this.initialTabIndex = 0,
    this.refreshHomeOnEnter = false,
    this.refreshSource = 'navigation',
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentSlide = 0;
  final PageController _pageController = PageController(viewportFraction: 1.0);
  Timer? _timer;

  late HomeBloc _homeBloc;
  late SubscriptionBloc _subscriptionBloc;

  final ProfileRepository _profileRepository = ProfileRepository();
  final CategoryRepository _categoryRepository = CategoryRepository();
  final BannerRepository _bannerRepository = BannerRepository();
  final AuthStorage _authStorage = AuthStorage();
  final NotificationsRepository _notificationsRepository =
      NotificationsRepository();
  bool _hasUnreadNotifications = false;
  Customer? _profile;
  bool _isLoadingProfile = true;

  List<PromoBanner> _banners = [];
  bool _isLoadingBanners = true;

  List<WardrobeCategory> _wardrobeCategories = [];
  WardrobeCategory? _essentialsCategory;
  bool _isLoadingCategories = true;

  /// Guards against overlapping pull-to-refresh / concurrent refreshes.
  bool _isRefreshingHome = false;
  bool _didPostPaymentRefresh = false;

  int get _bannerSlideCount => _banners.length;

  Widget _buildSubscriptionContent(int tabIndex) {
    return const SubscriptionTabWidget();
  }
  @override
  void initState() {
    super.initState();
    _homeBloc = HomeBloc(initialBottomNavIndex: widget.initialTabIndex);
    _subscriptionBloc = SubscriptionBloc()
      ..add(LoadActiveSubscriptionEvent());
    if (widget.refreshHomeOnEnter) {
      _isLoadingProfile = true;
      _isLoadingCategories = true;
      _isLoadingBanners = true;
    } else {
      _loadProfile();
      _loadCategories();
      _loadBanners();
      _checkUnreadNotifications();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.refreshHomeOnEnter) {
        _refreshAfterPaymentSuccess();
        return;
      }
      context.read<CartBloc>().add(
        LoadCartEvent(
          forceRefresh: true,
          source: 'HomeScreen.initState',
        ),
      );
    });
  }

  Future<void> _refreshAfterPaymentSuccess() async {
    if (_didPostPaymentRefresh || _isRefreshingHome) return;
    _didPostPaymentRefresh = true;
    if (mounted) {
      setState(() {
        _isRefreshingHome = true;
      });
    }
    if (kDebugMode) {
      debugPrint('[HOME_REFRESH] START source=${widget.refreshSource}');
    }
    try {
      final errors = <Object>[];
      await Future.wait([
        _runHomeRefreshTask(
          () => _loadProfile(forceRefresh: true, propagateError: true),
          errors,
        ),
        _runHomeRefreshTask(
          () => _loadCategories(forceRefresh: true, propagateError: true),
          errors,
        ),
        _runHomeRefreshTask(
          () => _loadBanners(forceRefresh: true, propagateError: true),
          errors,
        ),
      ]);

      if (!mounted) return;
      // Cart was already refreshed in the payment-success handler before
      // navigation; skip the redundant GET unless the state is stale.
      final cartBloc = context.read<CartBloc>();
      if (cartBloc.state.status == CartStatus.initial) {
        final remoteCart = await cartBloc.refresh(
          source: 'HomeScreen.${widget.refreshSource}',
        );
        if (kDebugMode) {
          debugPrint('[CART_AFTER_PAYMENT] item_count=${remoteCart.itemCount}');
        }
      } else if (kDebugMode) {
        debugPrint(
          '[HOME_REFRESH] cart already refreshed, '
          'items=${cartBloc.state.totalItems}',
        );
      }
      if (kDebugMode) {
        debugPrint('[HOME_REFRESH] API_COMPLETE');
      }

      _subscriptionBloc.add(LoadActiveSubscriptionEvent());
      await SubscriptionGarmentBalance.resolveAndCache(forceRefresh: true);

      if (mounted && errors.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_homeRefreshErrorMessage(errors)),
              backgroundColor: const Color(0xFF2A2D36),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      if (kDebugMode) {
        debugPrint('[HOME_REFRESH] STATE_UPDATED');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingHome = false;
        });
      }
    }
  }

  Future<void> _loadProfile({
    bool forceRefresh = false,
    bool propagateError = false,
  }) async {
    if (forceRefresh && mounted) {
      setState(() => _isLoadingProfile = true);
    }
    final cached = ProfileCache.instance.customer;
    if (cached != null && !forceRefresh) {
      if (mounted) {
        setState(() {
          _profile = cached;
          _isLoadingProfile = false;
        });
      }
      return;
    }

    final token = await _authStorage.getAuthToken();
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _isLoadingProfile = false);
      return;
    }

    try {
      final profile = await _profileRepository.getProfile(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _isLoadingProfile = false;
      });
    } on ApiException {
      if (mounted) setState(() => _isLoadingProfile = false);
      if (propagateError) rethrow;
    } catch (_) {
      if (mounted) setState(() => _isLoadingProfile = false);
      if (propagateError) rethrow;
    }
  }

  Future<void> _loadCategories({
    bool forceRefresh = false,
    bool propagateError = false,
  }) async {
    if (forceRefresh && mounted) {
      setState(() => _isLoadingCategories = true);
    }
    if (!forceRefresh) {
      final cached = CategoryCache.instance.categories;
      if (cached != null) {
        if (mounted) {
          setState(() {
            _applyCategories(cached);
            _isLoadingCategories = false;
          });
        }
        return;
      }
    }

    final token = await _authStorage.getAuthToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _applyCategories(const []);
          _isLoadingCategories = false;
        });
      }
      return;
    }

    try {
      final categories = await _categoryRepository.getCategories(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _applyCategories(categories);
        _isLoadingCategories = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _applyCategories(const []);
        _isLoadingCategories = false;
      });
      if (propagateError) rethrow;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applyCategories(const []);
        _isLoadingCategories = false;
      });
      if (propagateError) rethrow;
    }
  }

  void _applyCategories(List<WardrobeCategory> categories) {
    WardrobeCategory? essentials;
    final cards = <WardrobeCategory>[];
    for (final category in categories) {
      if (essentials == null && category.isEssentials) {
        essentials = category;
      } else {
        cards.add(category);
      }
    }
    cards.sort((a, b) {
      final order = _wardrobeCardOrder(a).compareTo(_wardrobeCardOrder(b));
      if (order != 0) return order;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _wardrobeCategories = cards;
    _essentialsCategory = essentials;
  }

  int _wardrobeCardOrder(WardrobeCategory category) {
    final name = category.name.toLowerCase();
    if (name.contains('comfort')) return 0;
    if (name.contains('professional')) return 1;
    if (name.contains('premium')) return 2;
    if (name.contains('kids')) return 3;
    return 100;
  }

  Future<void> _loadBanners({
    bool forceRefresh = false,
    bool propagateError = false,
  }) async {
    if (forceRefresh && mounted) {
      setState(() => _isLoadingBanners = true);
    }
    // Skip memory cache when refreshing so admin updates are visible immediately.
    if (!forceRefresh) {
      final cached = BannerCache.instance.banners;
      if (cached != null) {
        if (mounted) {
          setState(() {
            _banners = cached;
            _isLoadingBanners = false;
          });
        }
        _startAutoSlider();
        return;
      }
    }

    final token = await _authStorage.getAuthToken();
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _isLoadingBanners = false);
      _startAutoSlider();
      return;
    }

    try {
      final banners = await _bannerRepository.getBanners(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _banners = banners;
        _isLoadingBanners = false;
        if (_currentSlide >= _bannerSlideCount) {
          _currentSlide = 0;
        }
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _isLoadingBanners = false);
      if (propagateError) rethrow;
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingBanners = false);
      if (propagateError) rethrow;
    }
    _startAutoSlider();
  }

  Future<void> _checkUnreadNotifications() async {
    final hasUnread = await _notificationsRepository.hasUnreadNotifications();
    if (mounted) {
      setState(() => _hasUnreadNotifications = hasUnread);
    }
  }

  /// Pull-to-refresh: re-fetch all Home tab APIs in parallel, then stop indicator.
  Future<void> _onHomePullToRefresh() async {
    if (_isRefreshingHome) return;
    if (mounted) {
      setState(() {
        _isRefreshingHome = true;
      });
    }

    try {
      // Profile header, wardrobe categories, and promo banners.
      final errors = <Object>[];
      await Future.wait([
        _runHomeRefreshTask(
          () => _loadProfile(forceRefresh: true, propagateError: true),
          errors,
        ),
        _runHomeRefreshTask(
          () => _loadCategories(forceRefresh: true, propagateError: true),
          errors,
        ),
        _runHomeRefreshTask(
          () => _loadBanners(forceRefresh: true, propagateError: true),
          errors,
        ),
        _checkUnreadNotifications(),
      ]);

      if (!mounted || errors.isEmpty) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_homeRefreshErrorMessage(errors)),
            backgroundColor: const Color(0xFF2A2D36),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingHome = false;
        });
      }
    }
  }

  Future<void> _runHomeRefreshTask(
    Future<void> Function() task,
    List<Object> errors,
  ) async {
    try {
      await task();
    } catch (error) {
      errors.add(error);
    }
  }

  String _homeRefreshErrorMessage(List<Object> errors) {
    for (final error in errors) {
      final text = error is ApiException ? error.message : error.toString();
      final lower = text.toLowerCase();
      if (lower.contains('network') ||
          lower.contains('connect') ||
          lower.contains('socket') ||
          lower.contains('offline') ||
          lower.contains('failed host lookup')) {
        return 'No Internet Connection';
      }
    }

    for (final error in errors) {
      if (error is ApiException && error.message.trim().isNotEmpty) {
        return error.message;
      }
    }

    return 'Unable to refresh. Please try again.';
  }

  void _startAutoSlider() {
    _timer?.cancel();
    if (_bannerSlideCount <= 1) return;

    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_pageController.hasClients) return;

      var nextPage = _currentSlide + 1;
      if (nextPage >= _bannerSlideCount) {
        nextPage = 0;
      }
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    _subscriptionBloc.close();
    _homeBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _subscriptionBloc,
      child: BlocProvider.value(
        value: _homeBloc,
        child: BlocListener<HomeBloc, HomeState>(
          listenWhen: (previous, current) =>
              current.bottomNavIndex != previous.bottomNavIndex,
          listener: (_, state) {
            // Reuse loaded data when switching tabs; no forced API reload here.
            // Subscription tab itself handles subscription reload on first entry.
            if (state.bottomNavIndex == 0) {
              _loadProfile();
            }
          },
          child: BlocBuilder<HomeBloc, HomeState>(
            builder: (context, state) {
              return Scaffold(
                backgroundColor: const Color(0xFF0F1012),
                body: SafeArea(
                  child: Column(
                    children: [
                      Expanded(child: _buildBody(state.bottomNavIndex)),
                      CustomBottomNav(currentIndex: state.bottomNavIndex),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(int index) {
    return IndexedStack(
      index: index,
      children: [
        _buildHomeContent(),
        const CategoriesScreen(isTab: true),
        CartScreen(
          key: const ValueKey('home_cart_tab'),
          isActive: index == 2,
        ),
        _buildSubscriptionContent(index),
        const ProfileScreen(isTab: true),
      ],
    );
  }

  bool get _isHomeShimmering {
    if (_isRefreshingHome) return true;
    final hasNoData = _banners.isEmpty && _wardrobeCategories.isEmpty;
    final isAnyLoading = _isLoadingCategories ||
        _isLoadingBanners ||
        (_isLoadingProfile && _profile == null);
    return hasNoData && isAnyLoading;
  }

  Widget _buildHomeContent() {
    // RefreshIndicator needs a scrollable child; AlwaysScrollable lets pull
    // work even when content is shorter than the viewport.
    return RefreshIndicator(
      color: AppColours.primary,
      backgroundColor: const Color(0xFF16181D),
      displacement: 40,
      onRefresh: _onHomePullToRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: _isHomeShimmering
            ? const HomeScreenShimmer()
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 20.h),
                    _buildHeader(),
                    SizedBox(height: 16.h),
                    Container(
                      height: 2,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xFFE6C27A).withOpacity(0.15),
                            Color(0xFFE6C27A),
                            Color(0xFFE6C27A).withOpacity(0.15),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),

                    _buildBannerSlider(),
                    SizedBox(height: 32.h),
                    _buildWardrobeSectionTitle(),
                    SizedBox(height: 20.h),
                    _buildWardrobeGrid(),
                    SizedBox(height: 24.h),
                    _buildEssentialsBanner(),
                    SizedBox(height: 40.h),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildWardrobeSectionTitle() {
    if (_isLoadingCategories && _wardrobeCategories.isEmpty) {
      return AppShimmer(
        child: AppShimmer.box(width: 210.w, height: 22.h, borderRadius: 6),
      );
    }
    return Text(
      "Choose Your Wardrobe",
      style: CustomTextStyles.montserratBold.copyWith(fontSize: 20),
    );
  }


  Widget _buildHeader() {
    if (_isRefreshingHome || (_isLoadingProfile && _profile == null)) {
      return const HomeHeaderShimmer();
    }

    final displayName = _profile?.fullName?.trim().isNotEmpty == true
        ? _profile!.fullName!
        : (_profile?.mobile ?? 'Guest');
    final photoUrl = _profile?.profilePhoto;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                height: 48.h,
                width: 48.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColours.primary, width: 1.5),
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.startsWith('http')
                      ? (() {
                          print('HOME PROFILE IMAGE =\n$photoUrl');
                          return Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            width: 48.w,
                            height: 48.h,
                            errorBuilder: (_, __, ___) => Image.asset(
                              ImageConstant.homeScreenImg2,
                              fit: BoxFit.cover,
                            ),
                          );
                        })()
                      : (() {
                          print('HOME PROFILE IMAGE URL = null (using asset)');
                          return Image.asset(
                            ImageConstant.homeScreenImg2,
                            fit: BoxFit.cover,
                          );
                        })(),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "WELCOME",
                      style: CustomTextStyles.openSansRegular.copyWith(
                        fontSize: 12,
                        color: AppColours.primary,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CustomTextStyles.montserratBold.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            // GestureDetector(
            //   onTap: () => Navigator.pushNamed(context, AppRoutes.favoritesScreen),
            //   child: Container(
            //     padding: EdgeInsets.all(10.w),
            //     decoration: BoxDecoration(
            //       color: const Color(0xFF1A1D21),
            //       shape: BoxShape.circle,
            //       border: Border.all(color: Colors.white10),
            //     ),
            //     child: Icon(Icons.favorite_border, color: AppColours.primary, size: 24),
            //   ),
            // ),
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: () async {
                setState(() => _hasUnreadNotifications = false);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
                if (mounted) {
                  setState(() => _hasUnreadNotifications = false);
                  _checkUnreadNotifications();
                }
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SvgPicture.asset(IconConstant.notification),
                  if (_hasUnreadNotifications)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColours.primary,
                          border: Border.all(
                            color: const Color(0xFF070A14),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          ],
        ),
      ],
    );
  }

  Widget _buildBannerSlider() {
    if (_isRefreshingHome || _isLoadingBanners) {
      return const BannerShimmer();
    }

    if (_banners.isEmpty) {
      return const SizedBox.shrink();
    }

    final slideCount = _bannerSlideCount;

    return SizedBox(
      height: 180.h,
      width: double.maxFinite,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentSlide = index;
          });
        },
        itemCount: slideCount,
        itemBuilder: (context, index) {
          final banner = _banners[index];
          return _buildBannerSlide(
            title: banner.title,
            subtitle: banner.description ?? '',
            imageUrl: banner.imageUrl,
            index: index,
            totalSlides: slideCount,
            isNetworkImage: true,
          );
        },
      ),
    );
  }

  Widget _buildBannerSlide({
    required String title,
    required String subtitle,
    required String imageUrl,
    required int index,
    required int totalSlides,
    bool isNetworkImage = false,
  }) {
    return Container(
      width: 380.w,
      margin: EdgeInsets.only(right: 10.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6C279), width: 0.4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isNetworkImage)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFF1A1D21),
                ),
              )
            else
              Image.asset(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            Container(
              color: Colors.black.withOpacity(0.35),
            ),
            Padding(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 10.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              title,
              style: CustomTextStyles.montserratBold.copyWith(fontSize: 20),
            ),

            SizedBox(height: 2.h),
            Text(
              subtitle,
              style: CustomTextStyles.openSansRegular.copyWith(
                fontSize: 12,
                color: AppColours.primary,
              ),
            ),
            SizedBox(height: 8.h),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE6C279),
                minimumSize: Size(138.w, 44.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 10.w),
              ),
              child: Text(
                "EXPLORE NOW",
                style: CustomTextStyles.openSansRegular.copyWith(
                  fontSize: 12,
                  color: AppColours.black,
                ),
              ),
            ),
            SizedBox(height: 4.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                totalSlides,
                (dotIndex) => Container(
                  width: dotIndex == _currentSlide ? 18.w : 7.w,
                  height: 6.h,
                  margin: EdgeInsets.symmetric(horizontal: 2.w),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: dotIndex == _currentSlide
                        ? const Color(0xFFE6C279)
                        : Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWardrobeGrid() {
    if (_isRefreshingHome || _isLoadingCategories) {
      return const WardrobeGridShimmer();
    }

    if (_wardrobeCategories.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24.h),
        child: Text(
          'No wardrobes available right now.',
          textAlign: TextAlign.center,
          style: CustomTextStyles.openSansRegular.copyWith(
            color: Colors.white54,
            fontSize: 14,
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < _wardrobeCategories.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: 24.h));
      rows.add(
        Row(
          children: [
            Expanded(child: _buildWardrobeCard(_wardrobeCategories[i])),
            if (i + 1 < _wardrobeCategories.length) ...[
              SizedBox(width: 20.w),
              Expanded(child: _buildWardrobeCard(_wardrobeCategories[i + 1])),
            ] else
              Expanded(child: SizedBox(height: 180.h)),
          ],
        ),
      );
    }

    return Column(children: rows);
  }

  String _wardrobeButtonLabel(WardrobeCategory category) {
    return category.isKids ? 'BUY' : 'CHOOSE';
  }

  Widget _buildWardrobeCard(WardrobeCategory category) {
    final title = category.name;
    final subtitle = category.featuresSubtitle;
    final buttonLabel = _wardrobeButtonLabel(category);

    return GestureDetector(
      onTap: () => _openWardrobe(category),
      child: Container(
        height: 180.h,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D21),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColours.primary.withOpacity(0.55),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFCFAF6E).withOpacity(0.12),
              blurRadius: 6,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ProductImage(
                imageUrl: category.imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(12.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: CustomTextStyles.montserratBold.copyWith(
                        fontSize: 11,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 4.h),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: CustomTextStyles.openSansRegular.copyWith(
                          fontSize: 8,
                          color: AppColours.primary,
                        ),
                      ),
                    ],
                    SizedBox(height: 12.h),
                    SizedBox(
                      height: 28.h,
                      width: 80.w,
                      child: ElevatedButton(
                        onPressed: () => _openWardrobe(category),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColours.primary,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          buttonLabel,
                          style: CustomTextStyles.openSansSemiBold.copyWith(
                            color: AppColours.black,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openWardrobe(WardrobeCategory category) {
    WardrobeBookingFlow.handleHomeCategoryChoose(
      context,
      wardrobeCategory: category.name,
      wardrobeCategoryId: category.id,
      isKidsCard: category.isKids,
      isEssentialsCard: category.isEssentials,
    );
  }

  Widget _buildEssentialsBanner() {
    if (_isRefreshingHome || _isLoadingCategories) {
      return const EssentialsBannerShimmer();
    }

    final essentials = _essentialsCategory;
    if (essentials == null) {
      return const SizedBox.shrink();
    }

    final title = essentials.name;
    final imageUrl = essentials.imageUrl;
    final subtitle = essentials.featuresSubtitle;

    return GestureDetector(
      onTap: () => _openWardrobe(essentials),
      child: Container(
        width: double.maxFinite,
        height: 180.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColours.primary, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE6C279).withOpacity(0.35),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: ProductImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.black.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16.w,
                right: 16.w,
                bottom: 14.h,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: AppColours.secondary,
                              fontSize: 16.fSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (subtitle != null) ...[
                            SizedBox(height: 4.h),
                            Text(
                              subtitle,
                              style: CustomTextStyles.openSansRegular.copyWith(
                                fontSize: 8,
                                color: AppColours.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 30.h,
                      child: ElevatedButton(
                        onPressed: () => _openWardrobe(essentials),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColours.primary,
                          padding: EdgeInsets.symmetric(horizontal: 40.w),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          "BUY",
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 11.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

