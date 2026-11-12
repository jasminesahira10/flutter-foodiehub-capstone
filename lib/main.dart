import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

const Color brandRed = Color(0xFFE53935);
const Color brandOrange = Color(0xFFFF8A65);
const Color pageBg = Color(0xFFFFF8F5);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Error catching: app crash aagaama error ah log pannum
  FlutterError.onError = (details) {
    debugPrint('App error: ${details.exceptionAsString()}');
  };
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    ChangeNotifierProvider(
      create: (_) => CartProvider()..loadCart(),
      child: const FoodieHubApp(),
    ),
  );
}

// ---------- DATA ----------
class MenuItem {
  final String id;
  final String name;
  final String emoji;
  final double price;
  final String category;
  final double rating;
  final String desc;
  const MenuItem(this.id, this.name, this.emoji, this.price, this.category,
      this.rating, this.desc);
}

const List<String> categories = ['All', 'Pizza', 'Burgers', 'Indian', 'Snacks', 'Drinks'];

const List<MenuItem> menu = [
  MenuItem('1', 'Margherita Pizza', '🍕', 199, 'Pizza', 4.5, 'Classic cheese and tomato'),
  MenuItem('2', 'Paneer Tikka Pizza', '🍕', 249, 'Pizza', 4.6, 'Spicy paneer, onion, capsicum'),
  MenuItem('3', 'Veg Burger', '🍔', 99, 'Burgers', 4.2, 'Crispy patty with fresh veggies'),
  MenuItem('4', 'Chicken Burger', '🍔', 149, 'Burgers', 4.4, 'Juicy chicken, cheese, sauce'),
  MenuItem('5', 'Chicken Biryani', '🍛', 249, 'Indian', 4.7, 'Aromatic rice with tender chicken'),
  MenuItem('6', 'Masala Dosa', '🥞', 79, 'Indian', 4.3, 'Crispy dosa with potato masala'),
  MenuItem('7', 'French Fries', '🍟', 89, 'Snacks', 4.1, 'Golden, crispy and salted'),
  MenuItem('8', 'Cold Coffee', '🥤', 99, 'Drinks', 4.4, 'Chilled creamy coffee'),
  MenuItem('9', 'Mango Shake', '🥭', 109, 'Drinks', 4.5, 'Fresh mango, thick and sweet'),
];

const Map<String, List<Color>> categoryColors = {
  'Pizza': [Color(0xFFFFE0B2), Color(0xFFFFCC80)],
  'Burgers': [Color(0xFFFFCCBC), Color(0xFFFFAB91)],
  'Indian': [Color(0xFFFFF9C4), Color(0xFFFFF176)],
  'Snacks': [Color(0xFFFFECB3), Color(0xFFFFE082)],
  'Drinks': [Color(0xFFB3E5FC), Color(0xFF81D4FA)],
};

// ---------- STATE (Provider) + LOCAL STORAGE ----------
class CartProvider extends ChangeNotifier {
  final Map<String, int> _qty = {};

  int quantityOf(String id) => _qty[id] ?? 0;
  int get count => _qty.values.fold(0, (a, b) => a + b);
  bool get isEmpty => _qty.isEmpty;

  double get subtotal {
    double sum = 0;
    for (final item in menu) {
      sum += quantityOf(item.id) * item.price;
    }
    return sum;
  }

  // Free delivery above Rs.300
  double get deliveryFee => (subtotal == 0 || subtotal >= 300) ? 0 : 30;
  double get grandTotal => subtotal + deliveryFee;

  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cart_v2', jsonEncode(_qty));
    } catch (e) {
      debugPrint('Could not save cart: $e');
    }
  }

  Future<void> loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('cart_v2');
      if (data != null) {
        final Map<String, dynamic> saved = jsonDecode(data);
        _qty
          ..clear()
          ..addAll(saved.map((k, v) => MapEntry(k, v as int)));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Could not load cart: $e');
    }
  }

  void add(MenuItem item) {
    _qty[item.id] = quantityOf(item.id) + 1;
    notifyListeners();
    _saveCart();
  }

  void remove(MenuItem item) {
    final q = quantityOf(item.id);
    if (q <= 1) {
      _qty.remove(item.id);
    } else {
      _qty[item.id] = q - 1;
    }
    notifyListeners();
    _saveCart();
  }

  // Cloud database: order ah Firestore la save pannum
  Future<String?> placeOrder() async {
    if (_qty.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    final lines = menu
        .where((m) => quantityOf(m.id) > 0)
        .map((m) => '${quantityOf(m.id)} x ${m.name}')
        .toList();

    final doc = await FirebaseFirestore.instance.collection('orders').add({
      'uid': user.uid,
      'lines': lines,
      'subtotal': subtotal,
      'delivery': deliveryFee,
      'total': grandTotal,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _qty.clear();
    notifyListeners();
    await _saveCart();
    return doc.id.substring(0, 6).toUpperCase();
  }
}

// ---------- APP ----------
class FoodieHubApp extends StatelessWidget {
  const FoodieHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoodieHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brandRed),
        scaffoldBackgroundColor: pageBg,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.hasData ? const HomeScreen() : const AuthScreen();
        },
      ),
    );
  }
}

// ---------- LOGIN / REGISTER ----------
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLogin = true;
  bool loading = false;
  bool hidePassword = true;
  String? error;

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (!email.contains('@')) {
      setState(() => error = 'Enter a valid email');
      return;
    }
    if (password.length < 6) {
      setState(() => error = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (isLogin) {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
      } else {
        await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [brandRed, brandOrange],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const Text('🍕', style: TextStyle(fontSize: 64)),
                  const Text('FoodieHub',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const Text('Delicious food, delivered fast',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 20,
                            offset: Offset(0, 8)),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(isLogin ? 'Welcome back' : 'Create account',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 20),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passwordController,
                          obscureText: hidePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(hidePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => hidePassword = !hidePassword),
                            ),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red)),
                          ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: FilledButton(
                            onPressed: loading ? null : submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: brandRed,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: loading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Text(isLogin ? 'Login' : 'Create Account',
                                    style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            isLogin = !isLogin;
                            error = null;
                          }),
                          child: Text(isLogin
                              ? 'New user? Register'
                              : 'Already have an account? Login'),
                        ),
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
}

// ---------- HOME (bottom navigation) ----------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  final pages = const [MenuTab(), CartTab(), OrdersTab(), ProfileTab()];

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Text('🍕', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Text('FoodieHub',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: brandRed)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: brandRed),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
            icon: Badge(
              label: Text('${cart.count}'),
              isLabelVisible: cart.count > 0,
              child: const Icon(Icons.shopping_bag_outlined),
            ),
            selectedIcon: Badge(
              label: Text('${cart.count}'),
              isLabelVisible: cart.count > 0,
              child: const Icon(Icons.shopping_bag),
            ),
            label: 'Cart',
          ),
          const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Orders'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------- Small quantity control (reusable) ----------
class QtyControl extends StatelessWidget {
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const QtyControl(
      {super.key,
      required this.qty,
      required this.onAdd,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (qty == 0) {
      return SizedBox(
        height: 34,
        child: FilledButton(
          onPressed: onAdd,
          style: FilledButton.styleFrom(
            backgroundColor: brandRed,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('ADD', style: TextStyle(fontSize: 13)),
        ),
      );
    }
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: brandRed,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.remove, color: Colors.white, size: 18),
            ),
          ),
          Text('$qty',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          InkWell(
            onTap: onAdd,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.add, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- TAB 1: Home (search + categories + grid) ----------
class MenuTab extends StatefulWidget {
  const MenuTab({super.key});

  @override
  State<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<MenuTab> {
  String query = '';
  String category = 'All';

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final email = FirebaseAuth.instance.currentUser?.email ?? 'friend';
    final name = email.split('@').first;

    final items = menu.where((m) {
      final matchCat = category == 'All' || m.category == category;
      final matchQuery = m.name.toLowerCase().contains(query.toLowerCase());
      return matchCat && matchQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hi, $name 👋',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                const Text('What would you like to eat today?',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    hintText: 'Search food...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((c) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: category == c,
                          selectedColor: brandRed,
                          labelStyle: TextStyle(
                              color:
                                  category == c ? Colors.white : Colors.black87),
                          showCheckmark: false,
                          onSelected: (_) => setState(() => category = c),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: Text('No food found 😕')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                childAspectRatio: 0.74,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = items[i];
                  final colors = categoryColors[item.category]!;
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 4)),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: colors),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Text(item.emoji,
                                      style: const TextStyle(fontSize: 60)),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star,
                                            size: 14, color: Colors.amber),
                                        const SizedBox(width: 2),
                                        Text('${item.rating}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    Text(item.desc,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54)),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('₹${item.price.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    QtyControl(
                                      qty: cart.quantityOf(item.id),
                                      onAdd: () => cart.add(item),
                                      onRemove: () => cart.remove(item),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------- TAB 2: Cart ----------
class CartTab extends StatefulWidget {
  const CartTab({super.key});

  @override
  State<CartTab> createState() => _CartTabState();
}

class _CartTabState extends State<CartTab> {
  bool placing = false;

  Future<void> placeOrder(CartProvider cart) async {
    setState(() => placing = true);
    try {
      final orderId = await cart.placeOrder();
      if (orderId != null && mounted) {
        // In-app notification (animated)
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: const Icon(Icons.check_circle,
                      color: Colors.green, size: 80),
                ),
                const SizedBox(height: 12),
                const Text('Order Placed! 🎉',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Order #$orderId is confirmed and saved to the cloud.',
                    textAlign: TextAlign.center),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not place order. Check your internet and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => placing = false);
    }
  }

  Widget billRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
        fontSize: bold ? 18 : 14,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    if (cart.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🛒', style: TextStyle(fontSize: 64)),
            SizedBox(height: 8),
            Text('Your cart is empty',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text('Add some tasty food from Home',
                style: TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }
    final items = menu.where((m) => cart.quantityOf(m.id) > 0).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('My Cart',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...items.map((m) {
                final q = cart.quantityOf(m.id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient:
                              LinearGradient(colors: categoryColors[m.category]!),
                        ),
                        child: Text(m.emoji,
                            style: const TextStyle(fontSize: 30)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text('₹${(q * m.price).toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ),
                      QtyControl(
                        qty: q,
                        onAdd: () => cart.add(m),
                        onRemove: () => cart.remove(m),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              billRow('Subtotal', '₹${cart.subtotal.toStringAsFixed(0)}'),
              billRow(
                  'Delivery fee',
                  cart.deliveryFee == 0
                      ? 'FREE'
                      : '₹${cart.deliveryFee.toStringAsFixed(0)}'),
              const Divider(),
              billRow('Total', '₹${cart.grandTotal.toStringAsFixed(0)}',
                  bold: true),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: placing ? null : () => placeOrder(cart),
                  style: FilledButton.styleFrom(
                    backgroundColor: brandRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: placing
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Place Order',
                          style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- TAB 3: Orders (Firestore) ----------
class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});

  String formatDate(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day}/${d.month}/${d.year}  $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('uid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs.toList();
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🧾', style: TextStyle(fontSize: 64)),
                SizedBox(height: 8),
                Text('No orders yet',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }
        docs.sort((a, b) {
          final ta =
              (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final tb =
              (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          if (ta == null) return -1;
          if (tb == null) return 1;
          return tb.compareTo(ta);
        });
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('My Orders',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              );
            }
            final data = docs[i - 1].data() as Map<String, dynamic>;
            final lines = (data['lines'] as List).join('\n');
            final total = (data['total'] as num).toStringAsFixed(0);
            final id = docs[i - 1].id.substring(0, 6).toUpperCase();
            final ts = data['createdAt'] as Timestamp?;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Order #$id',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Confirmed',
                            style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (ts != null)
                    Text(formatDate(ts.toDate()),
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12)),
                  const Divider(height: 20),
                  Text(lines),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('Total: ₹$total',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------- TAB 4: Profile (photo + location) ----------
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Uint8List? photoBytes;
  String locationText = 'Location not detected yet';
  String? error;
  bool loadingLocation = false;

  Future<void> pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        photoBytes = bytes;
        error = null;
      });
    } catch (e) {
      setState(() => error = 'Could not load photo. Please try again.');
    }
  }

  Future<void> getLocation() async {
    setState(() {
      loadingLocation = true;
      error = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => error = 'Location services are turned off.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() => error = 'Location permission was denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => error =
            'Location permission is blocked. Enable it in browser/app settings.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        locationText =
            'Lat: ${pos.latitude.toStringAsFixed(4)}, Lng: ${pos.longitude.toStringAsFixed(4)}';
      });
    } catch (e) {
      setState(() => error = 'Could not get location. Please try again.');
    } finally {
      if (mounted) setState(() => loadingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [brandRed, brandOrange]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(
                    radius: 52,
                    backgroundImage:
                        photoBytes != null ? MemoryImage(photoBytes!) : null,
                    child: photoBytes == null
                        ? const Icon(Icons.person, size: 56)
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(email,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => pickPhoto(ImageSource.gallery),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white)),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => pickPhoto(ImageSource.camera),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white)),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Icon(Icons.location_on, size: 40, color: brandRed),
                  const SizedBox(height: 8),
                  const Text('Delivery Location',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(locationText, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: loadingLocation ? null : getLocation,
                    style: FilledButton.styleFrom(backgroundColor: brandRed),
                    icon: loadingLocation
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.my_location),
                    label: const Text('Detect location'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}