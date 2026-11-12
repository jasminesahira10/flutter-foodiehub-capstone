# FoodieHub: Design and Architecture Documentation

FoodieHub is a Flutter food ordering app (web and mobile) built as the Codomax capstone project.

---

## 1. System Model

```
+------------------------------------------------------+
|                  FoodieHub (Flutter App)             |
|                                                      |
|  UI Screens                                          |
|  Login | Home | Cart | Orders | Profile              |
|        |                                             |
|  State Management: Provider (CartProvider)           |
|        |                                             |
|  +-----+-----------------+-----------------------+   |
|  | Local Storage         | Device Features       |   |
|  | shared_preferences    | geolocator (location) |   |
|  | (saves the cart)      | image_picker (photo)  |   |
|  +-----------------------+-----------------------+   |
+--------------------|---------------------------------+
                     | internet
+--------------------v---------------------------------+
|                 Firebase (Cloud)                     |
|  Authentication  : Email/Password login              |
|  Cloud Firestore : orders collection                 |
|  Hosting         : live website                      |
+------------------------------------------------------+
```

### Data flow: placing an order
1. User adds food on Home. CartProvider updates the cart and saves it locally.
2. User opens Cart and taps Place Order.
3. App writes an order document to Firestore (with the user's uid).
4. Cart is cleared and a confirmation dialog is shown.
5. Orders screen reads the user's orders live from Firestore.

---

## 2. UI Wireframes

### Login screen
```
+--------------------------+
|          [Logo]          |
|        FoodieHub         |
|  +--------------------+  |
|  | Email              |  |
|  | Password        (eye) |
|  | [   Login   ]      |  |
|  | New user? Register |  |
|  +--------------------+  |
+--------------------------+
```

### Home screen
```
+--------------------------+
| FoodieHub          Logout|
| Hi, user                 |
| [ Search food...       ] |
| (All)(Pizza)(Burgers)... |
| +--------+  +--------+   |
| | emoji  |  | emoji  |   |
| | name   |  | name   |   |
| | Rs  ADD|  | Rs  ADD|   |
| +--------+  +--------+   |
|--------------------------|
| Home  Cart Orders Profile|
+--------------------------+
```

### Cart screen
```
+--------------------------+
| My Cart                  |
| [emoji] Item    [- 2 +]  |
| [emoji] Item    [- 1 +]  |
|--------------------------|
| Subtotal            Rs.. |
| Delivery fee        Rs.. |
| Total               Rs.. |
| [     Place Order      ] |
+--------------------------+
```

### Orders and Profile screens
```
Orders                       Profile
+----------------------+     +----------------------+
| Order #A1B2C3  [Confirmed] | (photo) email        |
| 12/11/2026 5:30 PM   |     | [Gallery] [Camera]   |
| 2 x Veg Burger       |     | Delivery location    |
| Total: Rs 198        |     | [Detect location]    |
+----------------------+     +----------------------+
```

---

## 3. Backend Setup (Firebase)

| Item | Configuration |
|------|---------------|
| Project | cloud-notes-44136 |
| Authentication | Email/Password enabled |
| Database | Cloud Firestore (default), location nam5 |
| Hosting | Firebase Hosting (public folder: build/web) |
| Connection tool | FlutterFire CLI (generates lib/firebase_options.dart) |
| Packages | firebase_core, firebase_auth, cloud_firestore, provider, shared_preferences, geolocator, image_picker |

---

## 4. Architecture Schemas

### Firestore collection: orders
| Field | Type | Description |
|-------|------|-------------|
| uid | string | Owner's Firebase user id |
| lines | array of string | Items, for example "2 x Veg Burger" |
| subtotal | number | Sum of item prices |
| delivery | number | Delivery fee (free above Rs. 300) |
| total | number | subtotal + delivery |
| createdAt | timestamp | Server time of the order |

### Local storage (shared_preferences)
| Key | Value |
|-----|-------|
| cart_v2 | JSON map of item id to quantity, for example {"3": 2, "7": 1} |

### App data model (Dart)
```
MenuItem  : id, name, emoji, price, category, rating, desc
CartProvider : Map<String,int> quantities
               subtotal, deliveryFee, grandTotal
               add(), remove(), placeOrder(), loadCart()
```

---

## 5. Security Validation (Firestore Rules)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /orders/{orderId} {
      allow create: if request.auth != null
        && request.resource.data.uid == request.auth.uid;
      allow read: if request.auth != null
        && resource.data.uid == request.auth.uid;
    }
  }
}
```
Only logged-in users can create orders, and each user can read only their own orders.

### Input validation in the app
- Email must contain "@"
- Password must be at least 6 characters

---

## 6. Error Handling

| Situation | Behaviour |
|-----------|-----------|
| Wrong login details | Firebase error message shown on the login screen |
| Location permission denied | Friendly message, no crash |
| Photo cannot be loaded | Friendly message, no crash |
| Order fails (no internet) | Snackbar message, cart is kept |
| Unexpected Flutter errors | Logged with FlutterError.onError |