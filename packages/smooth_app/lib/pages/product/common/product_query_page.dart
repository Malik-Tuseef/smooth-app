import 'dart:async';
import 'dart:math';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:matomo_tracker/matomo_tracker.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/cards/product_cards/smooth_product_card_found.dart';
import 'package:smooth_app/data_models/product_list_supplier.dart';
import 'package:smooth_app/data_models/product_query_model.dart';
import 'package:smooth_app/generic_lib/animations/smooth_reveal_animation.dart';
import 'package:smooth_app/generic_lib/loading_dialog.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_error_card.dart';
import 'package:smooth_app/helpers/analytics_helper.dart';
import 'package:smooth_app/pages/personalized_ranking_page.dart';
import 'package:smooth_app/pages/product/common/product_query_page_helper.dart';
import 'package:smooth_app/themes/constant_icons.dart';
import 'package:smooth_app/views/bottom_sheet_views/group_query_filter_view.dart';
import 'package:smooth_app/widgets/ranking_floating_action_button.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

class ProductQueryPage extends StatefulWidget {
  const ProductQueryPage({
    required this.productListSupplier,
    required this.heroTag,
    required this.name,
    this.lastUpdate,
  });

  final ProductListSupplier productListSupplier;
  final String heroTag;
  final String name;
  final int? lastUpdate;

  @override
  State<ProductQueryPage> createState() => _ProductQueryPageState();
}

class _ProductQueryPageState extends State<ProductQueryPage>
    with TraceableClientMixin {
  // we have to use GlobalKey's for SnackBar's because of nested Scaffold's:
  // not the 2 Scaffold's here but one of them and the one on top (PageManager)
  final GlobalKey<ScaffoldMessengerState> _scaffoldKeyEmpty =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldKeyNotEmpty =
      GlobalKey<ScaffoldMessengerState>();
  bool _showBackToTopButton = false;
  late ScrollController _scrollController;

  late ProductQueryModel _model;
  int? _lastUpdate;

  @override
  String get traceTitle => 'search_page';

  @override
  String get traceName => 'Opened search_page';

  @override
  void initState() {
    super.initState();
    _lastUpdate = widget.lastUpdate;
    _model = ProductQueryModel(widget.productListSupplier);
    _scrollController = ScrollController()
      ..addListener(() {
        setState(() {
          if (_scrollController.offset >= 400) {
            _showBackToTopButton = true;
          } else {
            _showBackToTopButton = false;
          }
        });
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProductQueryModel>.value(
      value: _model,
      builder: (BuildContext context, Widget? wtf) {
        context.watch<ProductQueryModel>();
        final AppLocalizations appLocalizations = AppLocalizations.of(context);
        final Size screenSize = MediaQuery.of(context).size;
        final ThemeData themeData = Theme.of(context);
        if (_model.loadingStatus == LoadingStatus.LOADED) {
          _model.process(appLocalizations.category_all);
        }
        switch (_model.loadingStatus) {
          case LoadingStatus.POST_LOAD_STARTED:
          case LoadingStatus.LOADING:
          case LoadingStatus.LOADED:
            return _getEmptyScreen(
              screenSize,
              themeData,
              const CircularProgressIndicator(),
            );
          case LoadingStatus.COMPLETE:
            if (_model.isNotEmpty()) {
              _showRefreshSnackBar(_scaffoldKeyNotEmpty);
              AnalyticsHelper.trackSearch(
                search: widget.name,
                searchCategory: _model.currentCategory,
                searchCount: _model.displayProducts?.length,
              );
              return _getNotEmptyScreen(
                screenSize,
                themeData,
                appLocalizations,
              );
            }
            _showRefreshSnackBar(_scaffoldKeyEmpty);
            return _getEmptyScreen(
              screenSize,
              themeData,
              _getEmptyText(
                themeData,
                appLocalizations.no_product_found,
              ),
            );
          case LoadingStatus.ERROR:
            return _getErrorWidget(
                screenSize, themeData, '${_model.loadingError}');
        }
      },
    );
  }

  Widget _getEmptyScreen(
    final Size screenSize,
    final ThemeData themeData,
    final Widget emptiness,
  ) =>
      ScaffoldMessenger(
        key: _scaffoldKeyEmpty,
        child: SmoothScaffold(
          appBar: AppBar(
            backgroundColor: themeData.scaffoldBackgroundColor,
            leading: const _BackButton(),
            title: _getAppBarTitle(),
          ),
          body: Hero(
            tag: widget.heroTag,
            child: Center(child: emptiness),
          ),
        ),
      );

  Widget _getAppBarTitle() => AutoSizeText(widget.name, maxLines: 2);

  Widget _getNotEmptyScreen(
    final Size screenSize,
    final ThemeData themeData,
    final AppLocalizations appLocalizations,
  ) =>
      ScaffoldMessenger(
        key: _scaffoldKeyNotEmpty,
        child: SmoothScaffold(
          floatingActionButton: Row(
            mainAxisAlignment: _showBackToTopButton
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: <Widget>[
              RankingFloatingActionButton(
                onPressed: () => Navigator.push<Widget>(
                  context,
                  MaterialPageRoute<Widget>(
                    builder: (BuildContext context) => PersonalizedRankingPage(
                      products: _model.displayProducts!,
                      title: widget.name,
                    ),
                  ),
                ),
              ),
              Visibility(
                visible: _showBackToTopButton,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _showBackToTopButton ? 1.0 : 0.0,
                  child: SmoothRevealAnimation(
                    animationCurve: Curves.easeInOutBack,
                    startOffset: const Offset(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: FloatingActionButton(
                        backgroundColor: themeData.colorScheme.secondary,
                        onPressed: () {
                          _scrollToTop();
                        },
                        tooltip: appLocalizations.go_back_to_top,
                        child: Icon(
                          Icons.arrow_upward,
                          color: themeData.colorScheme.onSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: <Widget>[
              _getHero(screenSize, themeData),
              RefreshIndicator(
                onRefresh: () => refreshList(),
                child: Scrollbar(
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: <Widget>[
                      SliverAppBar(
                        backgroundColor: themeData.scaffoldBackgroundColor,
                        pinned: true,
                        elevation: 0,
                        automaticallyImplyLeading: false,
                        leading: const _BackButton(),
                        actions: <Widget>[
                          TextButton.icon(
                            icon: const Icon(Icons.filter_list),
                            label: Text(
                              appLocalizations.filter,
                              style: themeData.textTheme.subtitle1,
                            ),
                            onPressed: () {
                              showCupertinoModalBottomSheet<Widget>(
                                expand: false,
                                context: context,
                                backgroundColor: Colors.transparent,
                                bounce: true,
                                builder: (BuildContext context) =>
                                    GroupQueryFilterView(
                                  categories: _model.categories,
                                  categoriesList: _model.sortedCategories,
                                  callback: (String category) {
                                    _model.selectCategory(category);
                                    setState(() {});
                                  },
                                ),
                              );
                            },
                          )
                        ],
                        title: _getAppBarTitle(),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) {
                            if (index >= _model.displayProducts!.length) {
                              // final button
                              final int already =
                                  _model.displayProducts!.length;
                              final int totalSize =
                                  _model.supplier.partialProductList.totalSize;
                              final int next = max(
                                0,
                                min(
                                  _model.supplier.productQuery.pageSize,
                                  totalSize - already,
                                ),
                              );
                              final Widget child;
                              if (next == 0) {
                                child = Text(
                                  appLocalizations
                                      .product_search_no_more_results(
                                    totalSize,
                                  ),
                                );
                              } else {
                                child = ElevatedButton.icon(
                                  icon: const Icon(Icons.download_rounded),
                                  label: Text(
                                    appLocalizations
                                        .product_search_button_download_more(
                                      next,
                                      already,
                                      totalSize,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final bool? error =
                                        await LoadingDialog.run<bool>(
                                      context: context,
                                      future: _model.loadNextPage(),
                                    );
                                    if (error != true) {
                                      await LoadingDialog.error(
                                        context: context,
                                        title: _model.loadingError,
                                      );
                                    }
                                  },
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 90.0, left: 20, right: 20),
                                child: child,
                              );
                            }
                            final Product product =
                                _model.displayProducts![index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 8.0,
                              ),
                              child: SmoothProductCardFound(
                                heroTag: product.barcode!,
                                product: product,
                              ),
                            );
                          },
                          childCount: _model.displayProducts!.length + 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _getHero(final Size screenSize, final ThemeData themeData) => Hero(
      tag: widget.heroTag,
      child: Container(
        width: screenSize.width,
        height: double.infinity,
        padding: const EdgeInsets.only(left: 10.0, right: 10.0, top: 96.0),
      ));

  Widget _getErrorWidget(
    final Size screenSize,
    final ThemeData themeData,
    final String errorMessage,
  ) {
    return _getEmptyScreen(
      screenSize,
      themeData,
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: SmoothErrorCard(
          errorMessage: errorMessage,
          tryAgainFunction: retryConnection,
        ),
      ),
    );
  }

  Widget _getEmptyText(
    final ThemeData themeData,
    final String message,
  ) =>
      Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: themeData.textTheme.subtitle1!.copyWith(fontSize: 18.0),
            ),
          ),
        ],
      );

  void _showRefreshSnackBar(
    final GlobalKey<ScaffoldMessengerState> scaffoldKey,
  ) {
    if (_lastUpdate == null) {
      return;
    }
    final ProductListSupplier? refreshSupplier =
        _model.supplier.getRefreshSupplier();
    if (refreshSupplier == null) {
      return;
    }
    final String lastTime =
        ProductQueryPageHelper.getDurationStringFromTimestamp(
            _lastUpdate!, context);
    final String message =
        '${AppLocalizations.of(context).cached_results_from} $lastTime';
    _lastUpdate = null;

    Future<void>.delayed(
      Duration.zero,
      () => scaffoldKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: AppLocalizations.of(context).label_refresh,
            onPressed: () async {
              final bool? error = await LoadingDialog.run<bool>(
                context: context,
                future: _model.loadFromTop(),
              );
              if (error != true) {
                await LoadingDialog.error(context: context);
              }
            },
          ),
        ),
      ),
    );
  }

  void retryConnection() {
    setState(() {
      _model = ProductQueryModel(widget.productListSupplier);
    });
  }

  Future<void> refreshList() async {
    final ProductListSupplier? refreshSupplier =
        widget.productListSupplier.getRefreshSupplier();
    setState(
      // How do we refresh a supplier that has no refresher? With itself.
      () => _model =
          ProductQueryModel(refreshSupplier ?? widget.productListSupplier),
    );
    return;
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(seconds: 3),
      curve: Curves.linear,
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(ConstantIcons.instance.getBackIcon()),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () {
          Navigator.maybePop(context);
        },
      );
}
