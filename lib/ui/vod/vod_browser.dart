import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/vod/vod_models.dart';
import '../../state/vod_controller.dart';
import '../keys.dart';
import '../widgets/focus_tile.dart';
import 'vod_detail.dart';
import 'vod_widgets.dart';

/// Zone navigabili col telecomando.
enum _Zone { top, side, grid }

/// Voce dell'elenco a sinistra.
class _Cat {
  const _Cat(this.id, this.name, this.count, {this.icon});
  final String id;
  final String name;
  final int count;
  final IconData? icon;
}

/// Sezione Film / Serie TV: categorie a sinistra, locandine a destra,
/// ricerca con tastiera a schermo e ordinamento.
class VodBrowser extends StatefulWidget {
  const VodBrowser({
    super.key,
    required this.initial,
    required this.onClose,
    this.onGames,
  });

  final VodKind initial;

  /// Va alla sala giochi.
  final VoidCallback? onGames;

  /// Torna alla TV in diretta.
  final VoidCallback onClose;

  @override
  State<VodBrowser> createState() => _VodBrowserState();
}

class _VodBrowserState extends State<VodBrowser> {
  final _focus = FocusNode(debugLabel: 'vod');
  final _grid = ScrollController();
  final _side = ScrollController();
  late final VodController _vod = context.read<VodController>();

  late VodKind _kind = widget.initial;
  _Zone _zone = _Zone.grid;

  /// Barra in alto: TV, Film, Serie, Cerca, Ordina.
  int _top = 1;
  int _sideIdx = 0;
  int _gridIdx = 0;
  int _cols = 5;
  double _rowExtent = 300;

  String _search = '';
  bool _keyboard = false;
  int _keyIdx = 0;
  VodSort _sort = VodSort.recent;
  String _category = VodCategories.all;

  /// Ultima posizione per ciascuna sezione.
  final _memory = <VodKind, (String, int, int)>{};

  List<VodItem>? _cache;
  Object? _cacheKey;

  @override
  void initState() {
    super.initState();
    _top = _kind == VodKind.movies ? 1 : 2;
    _vod.load(_kind);
    _pickStartCategory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    _grid.dispose();
    _side.dispose();
    super.dispose();
  }

  void _pickStartCategory() {
    final m = _memory[_kind];
    if (m != null) {
      _category = m.$1;
      _sideIdx = m.$2;
      _gridIdx = m.$3;
      return;
    }
    _category = _vod.continueWatching(_kind).isNotEmpty
        ? VodCategories.continueWatching
        : VodCategories.all;
    _gridIdx = 0;
    _sideIdx = _cats.indexWhere((c) => c.id == _category).clamp(0, 1 << 20);
  }

  void _switchKind(VodKind k) {
    if (k == _kind) return;
    _memory[_kind] = (_category, _sideIdx, _gridIdx);
    setState(() {
      _kind = k;
      _search = '';
      _keyboard = false;
      _pickStartCategory();
    });
    _vod.load(k);
    _jumpTo();
  }

  List<_Cat> get _cats {
    final c = _vod.catalog(_kind);
    final counts = _vod.counts(_kind);
    final cont = _vod.continueWatching(_kind).length;
    return [
      if (cont > 0)
        _Cat(
          VodCategories.continueWatching,
          'Continua a guardare',
          cont,
          icon: Icons.play_circle_outline_rounded,
        ),
      _Cat(
        VodCategories.all,
        _kind == VodKind.movies ? 'Tutti i film' : 'Tutte le serie',
        c.items.length,
        icon: Icons.apps_rounded,
      ),
      for (final cat in c.categories)
        if ((counts[cat.id] ?? 0) > 0)
          _Cat(cat.id, VodItem.cleanTitle(cat.name), counts[cat.id]!),
    ];
  }

  List<VodItem> get _items {
    final c = _vod.catalog(_kind);
    final key = (
      _kind,
      _category,
      _search,
      _sort,
      c.items,
      _category == VodCategories.continueWatching
          ? _vod.continueWatching(_kind).map((w) => w.key).join(',')
          : null,
    );
    if (_cacheKey == key && _cache != null) return _cache!;
    _cacheKey = key;
    return _cache = _vod.query(
      _kind,
      // Con una ricerca si cerca in tutto il catalogo.
      category: _search.isNotEmpty ? VodCategories.all : _category,
      search: _search,
      sort: _sort,
    );
  }

  double? _progressOf(VodItem i) {
    final w = _vod.progressOf(
      _kind == VodKind.movies ? 'm:${i.id}' : 's:${i.id}',
    );
    if (w == null || w.finished) return null;
    return w.fraction;
  }

  // --- Navigazione -----------------------------------------------------------

  void _jumpTo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealGrid(animate: false);
      _revealSide(animate: false);
    });
  }

  void _revealGrid({bool animate = true}) {
    if (!_grid.hasClients) return;
    final pos = _grid.position;
    final row = _gridIdx ~/ _cols;
    final target = (row * _rowExtent - _rowExtent * 0.35).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    final perf = context.read<PerformanceProfile>();
    if (!animate || perf.isLight) {
      _grid.jumpTo(target);
    } else {
      _grid.animateTo(target, duration: perf.fast, curve: Curves.easeOutCubic);
    }
  }

  static const _sideExtent = 46.0;

  void _revealSide({bool animate = true}) {
    if (!_side.hasClients) return;
    final pos = _side.position;
    final target =
        (_sideIdx * _sideExtent - pos.viewportDimension / 2 + _sideExtent)
            .clamp(0.0, pos.maxScrollExtent);
    _side.jumpTo(target);
  }

  void _setCategory(int i) {
    final cats = _cats;
    if (cats.isEmpty) return;
    i = i.clamp(0, cats.length - 1);
    setState(() {
      _sideIdx = i;
      _category = cats[i].id;
      _gridIdx = 0;
      _search = '';
    });
    _revealSide();
    _jumpTo();
  }

  void _moveGrid(int dx, int dy) {
    final n = _items.length;
    if (n == 0) {
      if (dx < 0) setState(() => _zone = _Zone.side);
      if (dy < 0) setState(() => _zone = _Zone.top);
      return;
    }
    final col = _gridIdx % _cols;
    if (dx < 0 && col == 0) {
      setState(() => _zone = _Zone.side);
      return;
    }
    if (dy < 0 && _gridIdx < _cols) {
      setState(() => _zone = _Zone.top);
      return;
    }
    var j = _gridIdx + dx + dy * _cols;
    if (dx > 0 && (col == _cols - 1 || j >= n)) return;
    if (j >= n) j = n - 1;
    if (j < 0) j = 0;
    setState(() => _gridIdx = j);
    _revealGrid();
  }

  void _open(VodItem item) async {
    await showVodDetail(context, kind: _kind, item: item);
    if (!mounted) return;
    _focus.requestFocus();
    setState(() {});
  }

  void _activateTop(int i) {
    switch (i) {
      case 0:
        widget.onClose();
      case 1:
        _switchKind(VodKind.movies);
      case 2:
        _switchKind(VodKind.series);
      case 3:
        widget.onGames?.call();
      case 4:
        setState(() {
          _keyboard = true;
          _zone = _Zone.side;
          _keyIdx = 0;
        });
      case 5:
        setState(() {
          _sort = VodSort.values[(_sort.index + 1) % VodSort.values.length];
          _gridIdx = 0;
        });
        _jumpTo();
    }
  }

  void _typeKey(String k) {
    setState(() {
      if (k == SearchKeyboard.delete) {
        if (_search.isNotEmpty) {
          _search = _search.substring(0, _search.length - 1);
        }
      } else if (k == SearchKeyboard.done) {
        _keyboard = false;
        _zone = _items.isEmpty ? _Zone.side : _Zone.grid;
      } else if (k == SearchKeyboard.space) {
        if (_search.isNotEmpty && !_search.endsWith(' ')) _search += ' ';
      } else {
        _search += k.toLowerCase();
      }
      _gridIdx = 0;
    });
    _jumpTo();
  }

  void _closeSearch() {
    setState(() {
      _keyboard = false;
      _search = '';
      _zone = _Zone.side;
      _gridIdx = 0;
    });
    _jumpTo();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final left = k == LogicalKeyboardKey.arrowLeft;
    final right = k == LogicalKeyboardKey.arrowRight;
    final up = k == LogicalKeyboardKey.arrowUp;
    final down = k == LogicalKeyboardKey.arrowDown;
    final ok = isSelectKey(k) && e is KeyDownEvent;
    final back = isBackKey(k) && e is KeyDownEvent;

    // Tastiera fisica: si scrive direttamente nella ricerca.
    final ch = e.character;
    if (ch != null &&
        ch.length == 1 &&
        RegExp(r'[a-zA-Z0-9àèéìòù]').hasMatch(ch) &&
        !(digitForKey(k) != null && !_keyboard && _search.isEmpty)) {
      setState(() {
        _keyboard = true;
        _search += ch.toLowerCase();
        _gridIdx = 0;
      });
      _jumpTo();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace && _search.isNotEmpty) {
      _typeKey(SearchKeyboard.delete);
      return KeyEventResult.handled;
    }

    switch (_zone) {
      case _Zone.top:
        if (left || right) {
          setState(() => _top = (_top + (right ? 1 : -1)).clamp(0, 5));
        } else if (down) {
          setState(() => _zone = _Zone.grid);
          if (_items.isEmpty) setState(() => _zone = _Zone.side);
        } else if (ok) {
          _activateTop(_top);
        } else if (back) {
          widget.onClose();
        }
      case _Zone.side:
        if (_keyboard) {
          if (left || right || up || down) {
            final j = SearchKeyboard.move(
              _keyIdx,
              left ? -1 : (right ? 1 : 0),
              up ? -1 : (down ? 1 : 0),
            );
            if (j != null) {
              setState(() => _keyIdx = j);
            } else if (right) {
              setState(() => _zone = _Zone.grid);
            } else if (up) {
              setState(() {
                _zone = _Zone.top;
                _top = 4;
              });
            }
          } else if (ok) {
            _typeKey(SearchKeyboard.keys[_keyIdx]);
          } else if (back) {
            _closeSearch();
          }
          break;
        }
        if (up) {
          if (_sideIdx == 0) {
            setState(() => _zone = _Zone.top);
          } else {
            _setCategory(_sideIdx - 1);
          }
        } else if (down) {
          _setCategory(_sideIdx + 1);
        } else if (right || ok) {
          if (_items.isNotEmpty) setState(() => _zone = _Zone.grid);
        } else if (back) {
          widget.onClose();
        }
      case _Zone.grid:
        if (left || right || up || down) {
          _moveGrid(left ? -1 : (right ? 1 : 0), up ? -1 : (down ? 1 : 0));
        } else if (k == LogicalKeyboardKey.pageDown ||
            k == LogicalKeyboardKey.channelDown) {
          _moveGrid(0, 3);
        } else if (k == LogicalKeyboardKey.pageUp ||
            k == LogicalKeyboardKey.channelUp) {
          _moveGrid(0, -3);
        } else if (ok) {
          final items = _items;
          if (_gridIdx < items.length) _open(items[_gridIdx]);
        } else if (back) {
          if (_search.isNotEmpty) {
            _closeSearch();
          } else {
            setState(() => _zone = _Zone.side);
          }
        }
    }
    return KeyEventResult.handled;
  }

  // --- Interfaccia -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    context.watch<VodController>();
    final catalog = _vod.catalog(_kind);
    final cats = _cats;
    final items = _items;
    if (_gridIdx >= items.length) {
      _gridIdx = items.isEmpty ? 0 : items.length - 1;
    }
    if (_sideIdx >= cats.length) _sideIdx = cats.isEmpty ? 0 : cats.length - 1;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 900;
    final pad = compact ? 16.0 : 36.0;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: Palette.ink,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.8, -1),
              radius: 1.6,
              colors: [Color(0xFF14213D), Palette.ink],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, pad * 0.7, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(compact),
                  SizedBox(height: compact ? 12 : 22),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: compact ? 210 : 290,
                          child: _keyboard ? _searchPane() : _sidePane(cats),
                        ),
                        SizedBox(width: compact ? 12 : 26),
                        Expanded(child: _gridPane(catalog, items, cats)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool compact) {
    final focusTop = _zone == _Zone.top;
    Widget pill(int i, String label, IconData icon, {bool active = false}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Pill(
            label: label,
            icon: icon,
            compact: compact,
            active: active,
            focused: focusTop && _top == i,
            onTap: () {
              setState(() => _top = i);
              _activateTop(i);
            },
          ),
        );
    return Row(
      children: [
        pill(0, 'TV in diretta', Icons.live_tv_rounded),
        pill(1, 'Film', Icons.movie_outlined, active: _kind == VodKind.movies),
        pill(
          2,
          'Serie TV',
          Icons.video_library_outlined,
          active: _kind == VodKind.series,
        ),
        pill(3, 'Giochi', Icons.sports_esports_rounded),
        const Spacer(),
        pill(
          4,
          _search.isEmpty ? 'Cerca' : '“$_search”',
          Icons.search_rounded,
          active: _keyboard || _search.isNotEmpty,
        ),
        pill(5, _sort.label, Icons.sort_rounded),
      ],
    );
  }

  Widget _searchPane() {
    final focused = _zone == _Zone.side;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('CERCA', style: AppText.overline),
        const SizedBox(height: 10),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: focused
                  ? Palette.accent
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            _search.isEmpty ? 'Scrivi un titolo…' : '$_search▏',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.headline.copyWith(
              color: _search.isEmpty
                  ? Palette.textTertiary
                  : Palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SearchKeyboard(
          focusedIndex: focused ? _keyIdx : null,
          onKey: (k) {
            setState(() {
              _zone = _Zone.side;
              _keyIdx = SearchKeyboard.keys.indexOf(k);
            });
            _typeKey(k);
          },
        ),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [KeyHint('OK', 'Scrivi'), KeyHint('Indietro', 'Chiudi')],
        ),
      ],
    );
  }

  Widget _sidePane(List<_Cat> cats) {
    final focused = _zone == _Zone.side;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('CATEGORIE', style: AppText.overline),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            controller: _side,
            itemExtent: _sideExtent,
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final c = cats[i];
              final active = c.id == _category && _search.isEmpty;
              final f = focused && i == _sideIdx;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _setCategory(i);
                  setState(() => _zone = _Zone.side);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: f
                        ? Colors.white
                        : active
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      if (c.icon != null) ...[
                        Icon(
                          c.icon,
                          size: 17,
                          color: f ? Palette.ink : Palette.accent,
                        ),
                        const SizedBox(width: 9),
                      ],
                      Expanded(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label.copyWith(
                            fontSize: 14,
                            color: f
                                ? Palette.ink
                                : active
                                ? Palette.textPrimary
                                : Palette.textSecondary,
                            fontWeight: active || f
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '${c.count}',
                        style: AppText.label.copyWith(
                          fontSize: 12,
                          color: f
                              ? Palette.ink.withValues(alpha: 0.6)
                              : Palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _gridPane(VodCatalog catalog, List<VodItem> items, List<_Cat> cats) {
    final title = _search.isNotEmpty
        ? 'Risultati per “$_search”'
        : cats.where((c) => c.id == _category).map((c) => c.name).firstOrNull ??
              '';
    Widget body;
    if (catalog.loading && catalog.items.isEmpty) {
      body = _message(
        _kind == VodKind.movies
            ? 'Carico i film della lista…'
            : 'Carico le serie della lista…',
        spinner: true,
      );
    } else if (catalog.error != null && catalog.items.isEmpty) {
      body = _message(catalog.error!);
    } else if (items.isEmpty) {
      body = _message(
        _search.isNotEmpty
            ? 'Nessun titolo trovato per “$_search”.'
            : _kind == VodKind.movies
            ? 'Nessun film in questa categoria.'
            : 'Nessuna serie in questa categoria.',
      );
    } else {
      body = LayoutBuilder(
        builder: (context, box) {
          final target = box.maxWidth < 700 ? 132.0 : 172.0;
          _cols = (box.maxWidth / target).floor().clamp(3, 9);
          final w = box.maxWidth / _cols;
          _rowExtent = (w - 14) * 1.5 + 14 + PosterTile.textHeight;
          return GridView.builder(
            controller: _grid,
            padding: const EdgeInsets.only(bottom: 40),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _cols,
              mainAxisExtent: _rowExtent,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => PosterTile(
              item: items[i],
              focused: _zone == _Zone.grid && i == _gridIdx,
              progress: _progressOf(items[i]),
              onTap: () {
                setState(() {
                  _zone = _Zone.grid;
                  _gridIdx = i;
                });
                _open(items[i]);
              },
            ),
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.display.copyWith(fontSize: 24),
              ),
            ),
            const SizedBox(width: 12),
            if (items.isNotEmpty)
              Text(
                '${items.length} ${items.length == 1 ? 'titolo' : 'titoli'}',
                style: AppText.label.copyWith(color: Palette.textTertiary),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: body),
      ],
    );
  }

  Widget _message(String text, {bool spinner = false}) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spinner) ...[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Palette.accent,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(fontSize: 16),
        ),
      ],
    ),
  );
}
