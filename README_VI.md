# Advanced Grid Trading EA

Expert Advisor MetaTrader 5 giao dịch lưới với ba loại lệnh độc lập (AA, BB, CC), gồng lãi (trailing profit), logic cân bằng theo phiên, scale theo vốn, khóa lãi và thông báo.

---

## Tổng quan

- **Grid (Lưới):** Giá cơ sở khi gắn EA, các bậc cách đều (pips), số bậc tối đa mỗi bên. Buy Stop trên đường cơ sở, Sell Stop dưới đường cơ sở.
- **AA, BB & CC:** Lot, Fixed/Geometric, hệ số nhân, lot tối đa, TP và magic riêng. Cùng một lưới; mỗi bậc có tối đa một AA, một BB và một CC (lệnh chờ hoặc lệnh đang mở). AA = Magic Number, BB = Magic Number + 1, CC = Magic Number + 2. Tất cả lệnh dùng chung một comment (ví dụ "EA Grid").
- **Phiên (Session):** Phiên hiện tại bắt đầu khi gắn EA hoặc khi EA thực hiện reset tự động. Mọi logic cân bằng và gồng lãi chỉ dùng lệnh đóng và P/L đóng trong phiên hiện tại. P/L gồm lãi/lỗ, swap và hoa hồng (khi có).

---

## 1. GRID (LƯỚI)

| Tham số | Mô tả |
|--------|--------|
| **Grid distance (pips)** | Khoảng cách giữa hai bậc lưới liền kề. |
| **Max grid levels per side** | Số bậc tối đa phía trên và phía dưới đường cơ sở. |

Các bậc cách đều. Không đặt lệnh tại đường cơ sở; bậc 1 gần đường cơ sở nhất, rồi bậc 2, 3, …

---

## 2. ORDERS (LỆNH)

### 2.1 AA (cài đặt)

- **Enable AA** – Bật/tắt AA (Buy Stop + Sell Stop).
- **Lot level 1** – Khối lượng cho bậc đầu tiên.
- **Fixed / Geometric** – Cách tính lot: Cố định hoặc Nhân (geometric theo bậc).
- **Lot multiplier** – Với Geometric: hệ số nhân cho bậc 2 trở lên.
- **Max lot** – Lot tối đa mỗi lệnh (0 = không giới hạn).
- **Take profit (pips)** – TP theo pips (0 = tắt).

**AA Auto balance (cặp)**

- Đóng một lệnh **lỗ** (phía ngược với đường cơ sở) + một lệnh **lãi** (cùng phía với giá) khi **tổng P/L của cặp ≥ ngưỡng** (USD). Lot hai bên có thể khác nhau. Giá phải cách đường cơ sở ít nhất **5 bậc lưới**. Cooldown (giây) sau khi đóng cặp. **Chỉ chạy khi P/L đóng phiên (sau khóa lãi) ≥ 0.**

**AA Balance by BB (Cân bằng AA theo BB)**

- Đóng **một lệnh AA đang lỗ** (phía ngược) khi **(P/L đóng BB trong phiên) + (P/L lệnh AA đó) ≥ ngưỡng** (USD). Chỉ trong phiên; giá phải cách đường cơ sở **5 bậc**; cooldown sau khi đóng. **Chỉ chạy khi P/L đóng BB trong phiên (sau khóa lãi) ≥ 0.**

### 2.2 Common (Magic & Comment)

- **Magic Number** – AA dùng magic này; BB = Magic + 1; CC = Magic + 2.
- **Order comment** – Comment chung cho mọi lệnh (ví dụ "EA Grid").

### 2.3 BB (cài đặt)

- Cấu trúc giống AA: Enable, lot, Fixed/Geometric, hệ số nhân, max lot, Take profit.

**BB Auto balance**

- Đóng **một lệnh BB đang lỗ** (phía ngược) khi **(P/L đóng BB trong phiên) + (P/L lệnh đó) ≥ ngưỡng** (USD). Ưu tiên đóng lệnh âm ít nhất trước. Chỉ trong phiên; giá cách đường cơ sở **5 bậc**; cooldown. **Chỉ chạy khi P/L đóng BB trong phiên (sau khóa lãi) ≥ 0.**

### 2.4 CC (cài đặt)

- Logic giống BB, tham số riêng: Enable, lot, Fixed/Geometric, hệ số nhân, max lot, Take profit.

**CC Auto balance**

- Đóng **một lệnh CC đang lỗ** (phía ngược) khi **(P/L đóng CC trong phiên) + (P/L lệnh đó) ≥ ngưỡng** (USD). Ưu tiên đóng lệnh âm ít nhất trước. Chỉ trong phiên; giá **5 bậc** từ đường cơ sở; cooldown. **Chỉ chạy khi P/L đóng CC trong phiên (sau khóa lãi) ≥ 0.**

---

## 3. SESSION: Trailing profit (Gồng lãi)

- **Enable trailing** – Khi lãi lệnh đang mở (phiên hiện tại) ≥ ngưỡng (USD), hủy toàn bộ lệnh chờ và bắt đầu gồng lãi SL (Buy/Sell) trên lệnh đang mở.
- **Start trailing when open profit ≥ (USD)** – Ngưỡng để vào chế độ gồng lãi.
- **Lock: close all when profit drops this % from peak** – Nếu lãi giảm từ đỉnh phiên đúng bằng % này thì đóng hết và reset (phiên mới).
- **Pips: SL distance / trailing step** – Khoảng cách SL so với giá và bước cập nhật gồng lãi.

Chỉ lệnh mở trong **phiên hiện tại** mới dùng cho gồng lãi. Thông báo gửi khi reset, không gửi khi vào chế độ gồng lãi.

---

## 3B. SESSION: Balance orders (Reset EA theo bậc lưới)

- **Enable** – Khi bật, EA có thể **reset** (đóng hết, đường cơ sở mới, đặt lại lệnh) khi:
  - Số bậc lưới có lệnh đang mở (phiên hiện tại) ≥ **Min grid levels**, và  
  - Tổng phiên (P/L đóng + P/L đang mở) ≥ **Session total threshold** (USD).

---

## 4. CAPITAL % SCALING (Scale theo % vốn)

- **Scale by capital growth** – Khi bật, **lot** (AA/BB/CC) và **ngưỡng gồng lãi (USD)** được nhân theo % tăng vốn so với vốn cơ sở.
- **Base capital (USD)** – 0 = dùng balance khi gắn EA; > 0 = dùng giá trị này. Vốn cơ sở đặt một lần và không đổi khi EA reset.
- **x% (max 100)** – Hệ số scale. Công thức: `multiplier = 1 + growth × (x/100)`, với `growth = (balance hiện tại − base) / base`. Multiplier bị giới hạn trong khoảng 0,1 đến 10. Ví dụ: base 50.000, hiện tại 75.000 → growth 50%; x = 50 → multiplier 1,25 → lot và ngưỡng gồng lãi × 1,25.

**Được scale:** Lot cơ sở AA/BB/CC và Ngưỡng gồng lãi (USD). TP/SL (pips) dùng giá trị input, không nhân với hệ số này.

---

## 5. NOTIFICATIONS (Thông báo)

- **Send notification when EA resets or stops** – Gửi thông báo khi reset toàn bộ hoặc dừng EA. Nội dung gồm lý do, chart, balance, %, drawdown tối đa, lot tối đa / tổng lệnh mở. Khi dùng khóa lãi, tin reset có dòng **Locked profit (saved, cumulative): X.XX USD**.

---

## 6. LOCK PROFIT (Khóa lãi – Save %)

**Ý nghĩa:** Khóa lãi = dự trữ một phần mỗi lần đóng lệnh có lãi để **số tiền này không tính vào logic cân bằng AA/BB/CC** (và không tính vào ngưỡng gồng lãi / tổng phiên để reset).

Khi bật:

- Mỗi lần đóng lệnh **có lãi** (P/L deal > 0), một **phần trăm** lợi nhuận đó (ví dụ 25%) được **khóa** vào quỹ dự trữ.
- **P/L deal** = Profit + Swap + Commission. Phần khóa = P/L deal × (Lock % / 100). Chỉ **phần còn lại** mới cộng vào P/L đóng phiên (và vào tổng phiên BB/CC nếu deal là BB/CC).
- **Phần đã khóa** **không** được tính vào:
  - Tổng P/L đóng dùng cho **cân bằng cặp AA**, **AA by BB**, **cân bằng BB**, **cân bằng CC**
  - Ngưỡng gồng lãi hoặc tổng phiên để reset.
- Quỹ khóa **tích lũy** và **không bao giờ bị reset** bởi EA. Tin reset hiển thị: **Locked profit (saved, cumulative): X.XX USD**.

**Tham số:**

- **Enable Lock Profit** – Bật/tắt tính năng.
- **Lock this %** – Phần trăm mỗi lần đóng lệnh có lãi để dự trữ (0–100). Ví dụ: 25 = khóa 25 USD từ 100 USD lãi; chỉ 75 USD được tính vào cân bằng/gồng lãi.

**Ví dụ minh họa (10% cất giữ):**

- Vốn ban đầu: **1000 USD**. Phiên bắt đầu = 1000 USD, P/L đóng phiên = 0.
- **Lệnh 1** đóng TP **+100 USD** → 10% cất giữ = 10 USD → **90 USD** được cộng vào “chi cho cân bằng”.
- **Lệnh 2** đóng TP **+200 USD** → 10% cất giữ = 20 USD → **180 USD** được cộng vào “chi cho cân bằng”.
- Tổng có thể chi cho cân bằng = 90 + 180 = **270 USD**. Lệnh 3 đang mở **âm 100 USD**.
- Điều kiện cân bằng thỏa: 270 + (−100) = 170 ≥ ngưỡng, P/L đóng phiên ≥ 0, và **số dư sau khi đóng ≥ 0** (170 ≥ 0) → EA **đóng lệnh 3** (lỗ 100).
- Sau khi đóng lệnh 3: P/L đóng phiên = **170 USD**. Quỹ cất giữ tích lũy = **30 USD**. Balance tài khoản = 1000 + 100 + 200 − 100 = **1200 USD**.
- **Nếu lệnh 3 là −300 USD:** 270 + (−300) = −30 &lt; 0 → EA **không** đóng (không chi vượt 270 có sẵn).
- **EA reset** → phiên mới, P/L đóng phiên **reset về 0**; lại tính từ đầu chỉ với các lệnh đóng của phiên mới.

---

## Phiên và cách tính P/L

- **Phiên hiện tại** bắt đầu khi:
  - **Gắn EA** vào chart, hoặc  
  - EA thực hiện **reset tự động** (gồng lãi lock, reset balance orders, hoặc đóng hết khi gồng lãi).
- Khi bắt đầu phiên, P/L đóng phiên và cooldown cân bằng được **reset về 0**; `sessionStartTime` được set. Mỗi lần EA reset = **phiên mới** (tính từ đầu). **Hệ số scale theo vốn** cập nhật khi init và sau mỗi lần reset toàn bộ (dùng balance hiện tại so với base).
- **P/L đóng** (cho tổng phiên và cân bằng) = **Profit + Swap + Commission** (theo deal). Khi bật Lock Profit: mỗi lần đóng **có lãi** thì tính % khóa (cất giữ); chỉ **phần còn lại** mới cộng vào P/L đóng phiên. Phần còn lại đó là số tiền **được phép chi cho cân bằng** (AA, BB, CC).
- **Quy tắc cân bằng:** Cân bằng (cặp AA, AA theo BB, BB, CC) **chỉ chạy khi** P/L đóng phiên tương ứng (sau khóa lãi) **≥ 0**. Nếu P/L đóng phiên âm thì không được chi cho cân bằng (không đóng lệnh lỗ).
- **Không chi vượt số có:** Chỉ đóng lệnh lỗ khi **sau khi đóng, số dư P/L phiên (của loại đó) vẫn ≥ 0**. Nếu lỗ lớn hơn số có thể chi (vd. có 270, lỗ 300 → 270 − 300 = −30) thì **không** đóng lệnh đó.
- **P/L lệnh đang mở** (cho cân bằng và gồng lãi) = **Profit + Swap** (hoa hồng tính khi đóng lệnh).
- Chỉ **deal có thời gian ≥ sessionStartTime** mới tính vào P/L đóng phiên. Chỉ **lệnh mở tại hoặc sau sessionStartTime** mới coi là “phiên hiện tại” cho logic gồng lãi và cân bằng.

---

## File

- **AdvancedGridTrading.mq5** – Một file EA; gắn vào chart trong MetaTrader 5.

---

## Phiên bản

2.01 – Advanced Grid Trading EA (Pro edition). AA, BB, CC; Khóa lãi; Scale theo % vốn; cân bằng và gồng lãi theo phiên.
