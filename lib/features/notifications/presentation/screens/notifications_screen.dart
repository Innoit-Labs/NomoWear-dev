import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/features/notifications/data/models/customer_notification.dart';
import 'package:nomowear/features/notifications/data/notifications_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsRepository _repository = NotificationsRepository();

  bool _isLoading = true;
  bool _isClearing = false;
  String? _errorMessage;
  List<CustomerNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _repository.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
      });

      // Mark all unread notifications as read on the backend
      await _markAllAsRead(items);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load notifications. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllAsRead(List<CustomerNotification> items) async {
    final unreadIds = items
        .where((n) => !n.isRead && n.notificationId.isNotEmpty)
        .map((n) => n.notificationId)
        .toList();

    if (unreadIds.isEmpty) return;

    await _repository.markNotificationsAsRead(unreadIds);
  }

  Future<void> _handleClearAll() async {
    if (_notifications.isEmpty || _isClearing) return;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF16181D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: const Color(0xFFE6C279).withOpacity(0.35),
            width: 1,
          ),
        ),
        title: Text(
          'Clear All Notifications',
          style: CustomTextStyles.openSansBold.copyWith(
            fontSize: 16,
            color: AppColours.primary,
          ),
        ),
        content: Text(
          'Are you sure you want to clear all notifications? This action cannot be undone.',
          style: CustomTextStyles.openSansRegular.copyWith(
            fontSize: 13,
            color: const Color(0xFFD0C5B4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              'Cancel',
              style: CustomTextStyles.openSansMedium.copyWith(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColours.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Clear All',
              style: CustomTextStyles.openSansSemiBold.copyWith(
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldClear != true || !mounted) return;

    setState(() => _isClearing = true);

    try {
      await _repository.clearAllNotifications();
      if (!mounted) return;

      setState(() {
        _notifications.clear();
        _isClearing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'All notifications cleared successfully',
            style: CustomTextStyles.openSansMedium.copyWith(color: Colors.black),
          ),
          backgroundColor: AppColours.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isClearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isClearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to clear notifications. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070A14),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFFE6C279).withOpacity(0.35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFFE6C279),
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Notifications',
                      textAlign: TextAlign.center,
                      style: CustomTextStyles.openSansBold.copyWith(
                        fontSize: 16,
                        color: AppColours.primary,
                      ),
                    ),
                  ),
                  if (_notifications.isNotEmpty)
                    GestureDetector(
                      onTap: _isClearing ? null : _handleClearAll,
                      child: _isClearing
                          ? SizedBox(
                              width: 14.w,
                              height: 14.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColours.primary,
                              ),
                            )
                          : Text(
                              'Clear All',
                              style: CustomTextStyles.openSansSemiBold.copyWith(
                                fontSize: 12,
                                color: AppColours.primary,
                              ),
                            ),
                    )
                  else
                    SizedBox(width: 20.w),
                ],
              ),
            ),
            Container(
              height: 2,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFFE6C27A).withOpacity(0.15),
                    const Color(0xFFE6C27A),
                    const Color(0xFFE6C27A).withOpacity(0.15),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColours.primary,
        ),
      );
    }

    if (_errorMessage != null && _notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: AppColours.primary.withOpacity(0.8),
              ),
              SizedBox(height: 12.h),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: CustomTextStyles.openSansMedium.copyWith(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 16.h),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColours.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _loadNotifications,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_notifications.isEmpty) {
      return RefreshIndicator(
        color: AppColours.primary,
        backgroundColor: const Color(0xFF16181D),
        onRefresh: _loadNotifications,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 100.h),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72.w,
                    height: 72.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColours.primary.withOpacity(0.08),
                      border: Border.all(
                        color: AppColours.primary.withOpacity(0.25),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.notifications_none_outlined,
                      size: 34,
                      color: AppColours.primary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'No Notifications',
                    style: CustomTextStyles.openSansBold.copyWith(
                      fontSize: 16,
                      color: AppColours.secondary,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40.w),
                    child: Text(
                      'You have no notifications right now. Order updates and announcements will appear here.',
                      textAlign: TextAlign.center,
                      style: CustomTextStyles.openSansRegular.copyWith(
                        fontSize: 13,
                        color: const Color(0xFFD0C5B4),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColours.primary,
      backgroundColor: const Color(0xFF16181D),
      onRefresh: _loadNotifications,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(12.w, 14.h, 12.w, 20.h),
        itemCount: _notifications.length,
        separatorBuilder: (_, __) => SizedBox(height: 16.h),
        itemBuilder: (_, index) {
          final item = _notifications[index];

          return Column(
            children: [
              /// CONTENT
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!item.isRead) ...[
                    Container(
                      width: 8,
                      height: 8,
                      margin: EdgeInsets.only(top: 6.h, right: 8.w),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColours.primary,
                      ),
                    ),
                  ],
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: CustomTextStyles.openSansSemiBold.copyWith(
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 10.h),
                          Text(
                            item.message,
                            style: CustomTextStyles.openSansRegular.copyWith(
                              fontSize: 12,
                              height: 22.75 / 12,
                              letterSpacing: 0,
                              color: const Color(0xFFD0C5B4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    item.formattedTime,
                    style: CustomTextStyles.openSansRegular.copyWith(
                      fontSize: 12,
                      color: AppColours.hintcolor,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),

              /// BOTTOM LINE
              Divider(
                color: const Color(0xFFE6C279).withOpacity(0.4),
                thickness: 0.8,
                height: 1,
              ),
            ],
          );
        },
      ),
    );
  }
}
