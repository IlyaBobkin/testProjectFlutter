import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = false;

  void setDarkMode(bool dark) {
    setState(() => isDarkMode = dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Каталог товаров',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      ),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: CatalogScreen(setDarkMode: setDarkMode, isDarkMode: isDarkMode),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ===================== МОДЕЛИ =====================
class Category {
  final String id;
  final String url;
  final String name;

  Category({required this.id, required this.url, required this.name});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(id: json['id'], url: json['url'], name: json['name']);
  }
}

class Product {
  final int id;
  final String name;
  final double price;
  final List<String> images;
  final List<String> sizes;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.images,
    required this.sizes,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    List<String> images = [];
    if (json['photos'] != null) {
      for (var photo in json['photos']) {
        if (photo['big'] != null) images.add(photo['big']);
      }
    }
    images = images.take(3).toList();

    List<String> sizes = [];
    if (json['sizes'] != null) {
      for (var s in json['sizes'].values) {
        sizes.add(s['name']);
      }
    }
    return Product(
      id: json['id'],
      name: json['name'] ?? 'Нет названия',
      price: (json['price'] ?? 0).toDouble(),
      images: images,
      sizes: sizes,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'price': price, 'images': images, 'sizes': sizes};
  }
}

// ===================== КОРЗИНА =====================
class CartItem {
  final Product product;
  String size;
  int quantity;

  CartItem({required this.product, required this.size, this.quantity = 1});

  Map<String, dynamic> toJson() {
    return {'product': product.toJson(), 'size': size, 'quantity': quantity};
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      product: Product.fromJson(json['product']),
      size: json['size'],
      quantity: json['quantity'],
    );
  }
}

class Cart {
  List<CartItem> items = [];

  Future<void> loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cartString = prefs.getString('cart');
    if (cartString != null) {
      List<dynamic> data = jsonDecode(cartString);
      items = data.map((e) => CartItem.fromJson(e)).toList();
    }
  }

  Future<void> saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('cart', jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  void addItem(Product product, String size) {
    final existing = items.where((i) => i.product.id == product.id && i.size == size).toList();
    if (existing.isNotEmpty) {
      existing.first.quantity += 1;
    } else {
      items.add(CartItem(product: product, size: size));
    }
    saveCart();
  }

  void removeItem(CartItem item) {
    items.remove(item);
    saveCart();
  }

  int get totalCount => items.fold(0, (sum, i) => sum + i.quantity);
  double get totalPrice => items.fold(0.0, (sum, i) => sum + i.quantity * i.product.price);
}

// ===================== ЭКРАН КАТАЛОГА =====================
class CatalogScreen extends StatefulWidget {
  final Function(bool) setDarkMode;
  final bool isDarkMode;

  const CatalogScreen({super.key, required this.setDarkMode, required this.isDarkMode});

  @override
  _CatalogScreenState createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<Category> categories = [];
  String selectedCategoryUrl = '';
  List<Product> products = [];
  bool isLoading = false;
  int currentPage = 1;
  bool hasMore = true;
  final ScrollController _scrollController = ScrollController();
  final Cart cart = Cart();

  @override
  void initState() {
    super.initState();
    cart.loadCart().then((_) => setState(() {}));
    fetchCategories();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !isLoading && hasMore) {
        fetchProducts();
      }
    });
  }

// ===================== ЗАГРУЗКА КАТЕГОРИЙ =====================
  Future<void> fetchCategories() async {
    const String url = 'https://api.lichi.com/category/get_category_detail';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'shop': 2,
        'lang': 1,
        'category': 'clothes',
      }),
    );

    print('Categories Response: ${response.statusCode}');
    print('Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List aMenu = data['api_data']['aMenu'] ?? [];

      final fetchedCategories = aMenu
          .where((json) => json['type'] == 'category')
          .map((json) => Category.fromJson(json))
          .toList();

      setState(() {
        categories = [Category(id: 'all', url: '', name: 'Все')];
        categories.addAll(fetchedCategories);
        selectedCategoryUrl = '';
      });

      await fetchProducts(reset: true);
    } else {
      print('Ошибка загрузки категорий: ${response.body}');
    }
  }

// ===================== ЗАГРУЗКА ТОВАРОВ =====================
  Future<void> fetchProducts({bool reset = false}) async {
    if (reset) {
      currentPage = 1;
      products.clear();
      hasMore = true;
    }
    if (!hasMore || isLoading) return;

    setState(() => isLoading = true);

    final body = <String, Object>{
      'shop': 2,
      'lang': 1,
      'limit': 12,
      'page': currentPage,
    };

    if (selectedCategoryUrl.isNotEmpty) {
      body['category'] = selectedCategoryUrl;
    }

    final response = await http.post(
      Uri.parse('https://api.lichi.com/category/get_category_product_list'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    print('Products Response: ${response.statusCode}');
    print('Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List aProduct = data['api_data']['aProduct'] ?? [];
      final fetchedProducts = aProduct.map((e) => Product.fromJson(e)).toList();

      if (fetchedProducts.length < 12) hasMore = false;
      products.addAll(fetchedProducts);
      currentPage++;
      setState(() {});
    } else {
      print('Ошибка загрузки товаров: ${response.body}');
    }

    setState(() => isLoading = false);
  }

  void showProductModal(Product product) {
    String? selectedSize = product.sizes.isNotEmpty ? product.sizes[0] : null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modalBg = isDark ? Colors.grey[900]! : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final inactiveBg = isDark ? Colors.grey[800]! : const Color(0xFFF5F5F5);
    final activeBg = Colors.black;
    final activeText = Colors.white;
    final inactiveText = textColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: modalBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Выберите размер',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 16),

              ...product.sizes.map((size) {
                final isAvailable = true;
                final isSelected = selectedSize == size;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: GestureDetector(
                    onTap: isAvailable
                        ? () => setModalState(() => selectedSize = size)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? activeBg : inactiveBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            size,
                            style: TextStyle(
                              color: isSelected ? activeText : inactiveText,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (!isAvailable)
                            Text(
                              'Нет в наличии',
                              style: TextStyle(color: Colors.red[400], fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 12),

              TextButton(
                onPressed: () {},
                child: Text(
                  'Как подобрать размер?',
                  style: TextStyle(color: Colors.blue[600]),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  onPressed: selectedSize == null
                      ? null
                      : () {
                    cart.addItem(product, selectedSize!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Добавлено в корзину')),
                    );
                    Navigator.pop(context);
                    setState(() {});
                  },
                  child: Text(
                    'В корзину · ${product.price.toStringAsFixed(0)} руб.',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        title: const Text('Каталог товаров', style: TextStyle(fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CartScreen(cart: cart)),
                ).then((_) => setState(() {}));
              },
              child: Container(
                width: 78,
                height: 45,
                decoration: BoxDecoration(
                  color: textColor,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      '${cart.totalCount}',
                      style: TextStyle(
                        color: bgColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Positioned(
                      left: 16,
                      child: SvgPicture.asset(
                        'images/cart_white.svg',
                        width: 18,
                        height: 18,
                        colorFilter: ColorFilter.mode(bgColor, BlendMode.srcIn),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Каждый день тысячи девушек раскладывают пакеты с новинками Lichi и становятся счастливее, ведь одежда, что новое платье может изменить день, а с ним и всю жизнь!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: textColor, fontWeight: FontWeight.w300),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5,vertical: 20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.setDarkMode(true),
                    icon: const Icon(Icons.nights_stay, size: 18),
                    label: const Text('Тёмная тема', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.isDarkMode ? Colors.grey.shade900 : Colors.grey.shade100,
                      foregroundColor: widget.isDarkMode ? Colors.grey.shade100 : Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 25),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.setDarkMode(false),
                    icon: const Icon(Icons.wb_sunny, size: 18),
                    label: const Text('Светлая тема', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !widget.isDarkMode ? Colors.black : Colors.white,
                      foregroundColor: !widget.isDarkMode ? Colors.white : Colors.black,
                      elevation: 0,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 25),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = cat.url == selectedCategoryUrl;
                return Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedCategoryUrl = cat.url;
                        fetchProducts(reset: true);
                      });
                    },
                    child: Column(
                      children: [
                        Text(
                          cat.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? textColor : Colors.grey,
                          ),
                        ),
                        if (isSelected)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            height: 2,
                            width: 24,
                            color: textColor,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          Expanded(
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.5,
                crossAxisSpacing: 5,
                mainAxisSpacing: 5,
              ),
              itemCount: products.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == products.length) return const Center(child: CircularProgressIndicator());
                final product = products[index];

                return StatefulBuilder(
                  builder: (context, setStateGrid) {
                    int currentPage = 0;
                    final PageController pageController = PageController();

                    return GestureDetector(
                      onTap: () => showProductModal(product),
                      child: Container(
                        decoration: BoxDecoration(
                          color: bgColor,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(15), bottom: Radius.circular(15)),
                              child: Stack(
                                children: [
                                  SizedBox(
                                    height: 270,
                                    width: double.infinity,
                                    child: PageView.builder(
                                      controller: pageController,
                                      onPageChanged: (i) => setStateGrid(() => currentPage = i),
                                      itemCount: product.images.length,
                                      itemBuilder: (ctx, i) => Image.network(
                                        product.images[i],
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                      ),
                                    ),
                                  ),
                                  if (product.images.length > 1)
                                    Positioned(
                                      bottom: 12,
                                      left: 0,
                                      right: 0,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: List.generate(product.images.length, (i) {
                                          return AnimatedContainer(
                                            duration: const Duration(milliseconds: 300),
                                            width: 7,
                                            height: 7,
                                            margin: const EdgeInsets.symmetric(horizontal: 3),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: i == currentPage ? Colors.white : Colors.white.withOpacity(0.5),
                                              border: Border.all(color: Colors.white, width: 1),
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    '${product.price.toStringAsFixed(0)} руб.',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    product.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: textColor,
                                      height: 1.3,
                                      fontWeight: FontWeight.w300
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== ЭКРАН КОРЗИНЫ =====================
class CartScreen extends StatefulWidget {
  final Cart cart;
  const CartScreen({super.key, required this.cart});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? Colors.grey[900]! : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Корзина'),
        backgroundColor: bgColor,
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      body: widget.cart.items.isEmpty
          ? const Center(child: Column(crossAxisAlignment: CrossAxisAlignment.center,mainAxisAlignment: MainAxisAlignment.center,children: [Text('Корзина пустая'), Text('Добавьте все что вы хотите.')],))
          : Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.cart.items.length,
              itemBuilder: (context, index) {
                final item = widget.cart.items[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: item.product.images.isNotEmpty
                            ? Image.network(
                          item.product.images[0],
                          width: 80,
                          height: 100,
                          fit: BoxFit.cover,
                        )
                            : Container(width: 80, height: 100, color: Colors.grey[300]),
                      ),
                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.product.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.size,
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${item.product.price.toStringAsFixed(0)} руб.',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                      Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 20),
                                onPressed: () => setState(() {
                                  if (item.quantity > 1) {
                                    item.quantity--;
                                  } else {
                                    widget.cart.removeItem(item);
                                  }
                                  widget.cart.saveCart();
                                }),
                                padding: EdgeInsets.zero,
                              ),
                              Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add, size: 20),
                                onPressed: () => setState(() {
                                  item.quantity++;
                                  widget.cart.saveCart();
                                }),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => setState(() {
                              widget.cart.removeItem(item);
                              widget.cart.saveCart();
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : const Color(0xFFF5F5F5),
              border: Border(top: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('К оплате', style: TextStyle(fontSize: 16)),
                Text('${widget.cart.totalPrice.toStringAsFixed(0)} руб.', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}