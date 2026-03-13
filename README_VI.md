# Advanced Grid Trading EA — Hướng dẫn đầy đủ

Expert Advisor MetaTrader 5 giao dịch **lưới** với bốn loại lệnh **AA, BB, CC, DD**, **gồng lãi**, **cân bằng** (chỉ đóng lỗ **AA/BB/CC**), **scale vốn**, **khóa lãi** (% tiết kiệm mỗi TP kể cả **DD**), và **thông báo** (có **giá lúc reset**).

---

## Mục lục

1. [Khái niệm](#1-khái-niệm)  
2. [Bảng tham số đầy đủ](#2-bảng-tham-số-đầy-đủ)  
3. [Lưới & cách đặt lệnh](#3-lưới--cách-đặt-lệnh)  
4. [AA/BB/CC (Stop) và DD (Limit)](#4-aabbcc-stop-và-dd-limit)  
5. [Phiên, pool và khóa lãi](#5-phiên-pool-và-khóa-lãi)  
6. [Quy tắc cân bằng (từng bước)](#6-quy-tắc-cân-bằng-từng-bước)  
7. [Ví dụ cân bằng](#7-ví-dụ-cân-bằng)  
8. [Gồng lãi](#8-gồng-lãi)  
9. [Scale vốn](#9-scale-vốn)  
10. [Thông báo](#10-thông-báo)  
11. [File & phiên bản](#11-file--phiên-bản)

---

## 1. Khái niệm

| Thuật ngữ | Ý nghĩa |
|-----------|--------|
| **Đường gốc (base)** | Giá tham chiếu khi **bắt đầu phiên** (gắn EA hoặc reset). Lưới xây quanh mức này. |
| **Phiên (session)** | Từ lúc attach/reset đến lần reset sau. Pool và gồng lãi chỉ tính deal **trong phiên hiện tại**. |
| **Pool cân bằng** | Tiền dùng để **đóng lệnh lỗ AA/BB/CC**. Chỉ được **nạp bởi lệnh chốt TP** (lãi sau khi trừ lock). **TP của DD cũng nạp pool** nhưng **không** đóng DD để cân bằng. |
| **Khóa lãi (lock)** | Một **%** mỗi lần chốt lãi bằng TP (AA/BB/CC/**DD**) để tiết kiệm. **Cộng dồn, không reset.** Cân bằng không tiêu phần này. |
| **Magic** | AA = Magic nhập; BB/CC/DD = +1, +2, +3. Một comment chung (vd. `EA Grid`). |

---

## 2. Bảng tham số đầy đủ

### 1. GRID

| Input | Mặc định | Mô tả |
|-------|----------|--------|
| Grid distance (pips) | 2000 | Khoảng cách giữa hai bậc liền kề. |
| Max grid levels per side | **40** | Số bậc tối đa **mỗi phía** trên/dưới gốc (tổng bậc = 2 × giá trị này). |

### 2. ORDERS — Common

| Input | Mặc định | Mô tả |
|-------|----------|--------|
| Magic Number | 123456 | AA = giá trị này; BB/CC/DD = +1, +2, +3. |
| Order comment | EA Grid | Chung cho mọi lệnh. |

### 2.2–2.4 AA / BB / CC

Mỗi khối: **Bật**, **Lot bậc 1**, **Fixed/Geometric**, **Hệ số nhân (bậc 2+)**, **Max lot (0 = không giới hạn)**, **TP (pips, 0 = tắt)**, **Bật cân bằng** (pool + lỗ ≥ 20 USD, cooldown 300 giây; chuẩn bị 3 bậc, thực hiện 5 bậc).

Mặc định thường gặp: AA lot 0.05, Geometric; BB tương tự; CC thường **Fixed** lot; TP BB/CC thường 2000 pips (nếu bật).

### 2.5 DD

| Input | Mặc định | Mô tả |
|-------|----------|--------|
| Enable DD | true | Sell Limit trên gốc + Buy Limit dưới gốc. |
| Lot bậc 1 | **0.01** | Lot cơ sở (vẫn scale nếu bật scale). |
| Fixed / Geometric | **Fixed** | Cách nhân lot theo bậc. |
| Max lot | 1.5 | Giới hạn/lệnh (0 = không giới hạn). |
| TP (pips) | 2000 | Đặt TP theo pips; 0 = tắt. |
| Cân bằng | — | **DD không có cân bằng** — EA không đóng DD để cân bằng. |

### 3. SESSION — Gồng lãi

| Input | Mặc định | Mô tả |
|-------|----------|--------|
| Enable trailing | true | Hủy pending, gồng SL khi lãi mở ≥ ngưỡng. |
| Ngưỡng lãi (USD) | **200** | Vào chế độ gồng. |
| Khi lãi giảm | Return | **Lock** = đóng hết + reset; **Return** = thoát gồng, đặt lại pending. |
| % giảm | 20 | Kích hoạt khi lãi giảm đúng % so với đỉnh. |
| Point A (pips) | 1500 | Neo SL từ bậc lưới tại thời điểm đạt ngưỡng. |
| Bước gồng (pips) | 1000 | Mỗi bước giá thì SL dời một bước. |
| Reset breakeven | false | Reset tùy chọn khi xa gốc và P/L + pool ≥ 0. |
| Số bậc tối thiểu breakeven | 10 | Đủ X bậc khỏi gốc mới xét breakeven reset. |

### 4. CAPITAL % SCALING

| Input | Mặc định | Mô tả |
|-------|----------|--------|
| Scale theo tăng vốn | true | Scale lot (AA/BB/CC/**DD**) và ngưỡng gồng (USD). |
| Base capital (USD) | **100000** | 0 = balance lúc attach; >0 = vốn cố định để tính multiplier. |
| x% scale | 50 | `multiplier = 1 + growth × (x/100)` có trần. |
| Max tăng % | 100 | Giới hạn multiplier (vd. 100 → tối đa 2.0). |

### 5. THÔNG BÁO

| Input | Mặc định | Mô tả |
|-------|----------|--------|
| Thông báo khi reset/dừng | true | Push (+ Telegram nếu bật). Có **Price at reset** (Bid). |
| Telegram | tắt | Cần token + Chat ID + cho phép WebRequest. |

### 6. LOCK PROFIT

| Input | Mặc định | Mô tả |
|-------|----------|--------|
| Bật | true | Trích % mỗi lần **chốt lãi TP** (AA/BB/CC/**DD**). |
| Lock % | 25 | Vd. 25 → khóa 25 USD từ 100 USD lãi; 75 USD vào pool. |

---

## 3. Lưới & cách đặt lệnh

- Các bậc **cách đều** theo Grid distance. **Không** đặt lệnh ngay tại đường gốc; bậc 1 gần gốc nhất, rồi 2, 3, …  
- EA bổ sung lệnh thiếu **từ bậc gần gốc ra xa**.  
- **Mỗi bậc tối đa một pending mỗi loại**; trùng thì xóa bớt.

**AA / BB / CC (lệnh Stop)**  
- **Buy Stop:** chỉ bậc **trên gốc** và **trên giá hiện tại** (giá lên mới khớp).  
- **Sell Stop:** chỉ bậc **dưới gốc** và **dưới giá hiện tại** (giá xuống mới khớp).

**DD (lệnh Limit)**  
- **Sell Limit:** bậc **trên gốc** — giá **xuống** chạm mức thì khớp bán.  
- **Buy Limit:** bậc **dưới gốc** — giá **lên** chạm mức thì khớp mua.

---

## 4. AA/BB/CC (Stop) và DD (Limit)

| | AA, BB, CC | DD |
|--|------------|-----|
| Loại lệnh chờ | Buy Stop / Sell Stop | Sell Limit (trên gốc) / Buy Limit (dưới gốc) |
| Cân bằng | Tùy từng loại bật/tắt | **Không** — không đóng DD để cân bằng |
| Pool | TP vào pool | **TP DD cũng vào pool** (giúp AA/BB/CC) |
| Khóa lãi | Có | **Có** — cùng % |
| Scale lot | Có | **Có** |

---

## 5. Phiên, pool và khóa lãi

- **Phiên** bắt đầu khi gắn EA hoặc reset; có thể reset bộ đếm pool.  
- **Chỉ deal đóng với lý do TP** mới cộng pool; SL/tay/stop out **không**.  
- Mỗi lần chốt lãi TP:  
  - P/L deal = Profit + Swap + Commission.  
  - Nếu bật lock: `locked = P/L × (Lock%/100)` → cộng vào **lockedProfitReserve** (không reset).  
  - **Phần còn lại** cộng vào **pool phiên**.  
- **Pool dùng chung** để cân bằng **chỉ AA/BB/CC**.  
- **Sàn:** sau khi đóng cân bằng, balance phải **≥ vốn đầu phiên + tổng đã khóa** để không tiêu hết tiết kiệm.

---

## 6. Quy tắc cân bằng (từng bước)

Trong code cố định: ngưỡng **20 USD**, cooldown **300 giây**, **3 bậc** chuẩn bị, **5 bậc** mới đóng.

1. **Chỉ phía đối diện:**  
   - Giá **trên gốc** → chỉ đóng **Sell đang lỗ** (dưới gốc). **Buy bị khóa** — không đóng Buy.  
   - Giá **dưới gốc** → chỉ đóng **Buy đang lỗ** (trên gốc). **Sell bị khóa**.

2. **Khoảng cách so với gốc:**  
   - **Chuẩn bị** (chọn lệnh lỗ xa nhất phía đối diện): giá **≥ 3 bậc** khỏi gốc.  
   - **Thực hiện đóng:** giá **≥ 5 bậc** **và** pool đủ.

3. **Thứ tự đóng:**  
   - **Xa đường gốc trước.**  
   - Cùng bậc: **AA → BB → CC**.

4. **Đóng một phần:** pool không đủ thì đóng **tỷ lệ lot**; deal comment **"Balance order"**.

5. **DD:** không bao giờ bị chọn để cân bằng; TP DD vẫn **làm đầy pool**.

---

## 7. Ví dụ cân bằng

**Giả sử:** Gốc = 1000. Bước 100 pips → trên: 1010, 1020, … dưới: 990, 980, …

**Vd.1 — Trên gốc**  
Giá 1200 (≥5 bậc). Sell dưới gốc lỗ −120, −80, −50 → đóng xa trước; không động Buy.

**Vd.2 — Dưới gốc**  
Giá 850 → chỉ đóng Buy trên gốc đang lỗ; không động Sell.

**Vd.3 — Một phần**  
Pool 60, cần 120 → đóng 50% lot; đợi thêm TP.

**Vd.4 — Cùng bậc**  
Cùng mức giá có AA, BB, CC → AA trước, BB giữa, CC sau.

**Vd.5 — Gần gốc**  
Giá trong vòng **5 bậc** → **không** thực hiện đóng cân bằng.

---

## 8. Gồng lãi

- Lãi mở ≥ **TrailingThresholdUSD** → hủy pending, quản lý SL (Point A rồi bước).  
- Chế độ **Lock:** lãi giảm X% từ đỉnh → đóng hết + reset phiên.  
- Chế độ **Return:** lãi giảm X% → thoát gồng, đặt lại lưới (theo logic SL đã đặt hay chưa).  
- Breakeven reset: bật thì khi đủ điều kiện có thể reset.

---

## 9. Scale vốn

- `growth = (balance hiện tại − baseCapital) / baseCapital` (hoặc 0 nếu base không hợp lệ).  
- `sessionMultiplier = 1 + growth × (AccountGrowthScalePct/100)`, có giới hạn trần.  
- Áp vào lot (AA/BB/CC/**DD**) và ngưỡng gồng (USD) khi bật scale.

---

## 10. Thông báo

Tin reset/dừng gồm:

- Chart, **Reason**  
- **Price at reset:** Bid tại thời điểm gửi  
- Initial balance at EA startup (không reset theo phiên)  
- Base capital, % scale  
- Balance hiện tại, % thay đổi so với lúc attach, drawdown, balance thấp nhất  
- **Locked profit (saved, cumulative)**  
- Telegram (nếu bật) — nội dung giống Push

Ví dụ:

```
EA RESET
Chart: GBPUSD
Reason: Trailing profit (SL hit)
Price at reset: 1.26543
--- SETTINGS ---
Initial balance at EA startup: 100000.00 USD
Base capital (USD): 100000.00
...
```

Thêm `https://api.telegram.org` vào danh sách **WebRequest** của MT5.

---

## 11. File & phiên bản

- **File:** `AdvancedGridTrading.mq5` — một file EA, gắn chart MT5.  
- **Phiên bản 2.07** — Bốn loại (AA/BB/CC Stop + DD Limit); pool từ TP cả bốn; cân bằng chỉ AA/BB/CC; khóa lãi mọi TP; thông báo có **Price at reset**.
