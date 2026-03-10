# Advanced Grid Trading EA

Expert Advisor MetaTrader 5 giao dịch lưới với ba loại lệnh độc lập (AA, BB, CC), gồng lãi (trailing profit), logic cân bằng theo phiên, scale theo vốn, khóa lãi (% tiền tiết kiệm) và thông báo.

---

## Tổng quan

- **Grid (Lưới):** Giá cơ sở khi gắn EA, các bậc cách đều (pips), số bậc tối đa mỗi bên. **Buy Stop** chỉ đặt ở bậc **trên đường gốc và trên giá hiện tại**; **Sell Stop** chỉ đặt ở bậc **dưới đường gốc và dưới giá hiện tại**. Bậc nào thiếu lệnh (theo loại AA/BB/CC đang bật) thì EA bổ sung.
- **AA, BB & CC:** Lot, Fixed/Geometric, hệ số nhân, lot tối đa, TP và magic riêng. Cùng một lưới; **mỗi bậc tối đa 1 lệnh mỗi loại** (theo input: bật AA thì tối đa 1 AA, bật BB thì 1 BB, bật CC thì 1 CC). AA = Magic Number, BB = Magic Number + 1, CC = Magic Number + 2. Tất cả lệnh dùng chung một comment (ví dụ "EA Grid").
- **Phiên (Session):** Phiên hiện tại bắt đầu khi gắn EA hoặc khi EA thực hiện reset tự động. Mọi logic cân bằng và gồng lãi chỉ dùng lệnh đóng và P/L đóng trong phiên hiện tại. **Chỉ lệnh đóng bởi Take Profit (TP)** mới cộng vào pool cân bằng; đóng bởi SL hoặc cắt tay không tính.
- **Pool cân bằng:** Pool = **chỉ lệnh đạt TP trong phiên hiện tại** trừ **%/$ tiết kiệm (lock) trong phiên hiện tại**. Chỉ phần còn lại dùng cho cân bằng. **Tiền lock (tiết kiệm) cộng dồn qua các phiên, không reset**; số $ lock đó **không dùng cho cân bằng** (sàn = vốn đầu phiên + lock nên cân bằng không bao giờ tiêu vào phần tiết kiệm).

---

## 1. GRID (LƯỚI)

| Tham số | Mô tả |
|--------|--------|
| **Grid distance (pips)** | Khoảng cách giữa hai bậc lưới liền kề. |
| **Max grid levels per side** | Số bậc tối đa phía trên và phía dưới đường cơ sở. |

Các bậc cách đều. Không đặt lệnh tại đường cơ sở; bậc 1 gần đường cơ sở nhất, rồi bậc 2, 3, …  
**Vị trí lệnh chờ:** Khi EA khởi động, đặt lệnh **từ bậc gần đường gốc ra xa** (bậc 1 trước, rồi 2, 3, …). Buy Stop tại bậc **trên đường gốc và trên giá hiện tại**; Sell Stop tại bậc **dưới đường gốc và dưới giá hiện tại**. Mỗi bậc tối đa 1 AA, 1 BB, 1 CC (theo loại đang bật); thiếu thì EA bổ sung.

---

## 2. ORDERS (LỆNH)

Thứ tự input: **Common** (Magic & Comment) trước, sau đó **AA**, **BB**, **CC** (mỗi loại có Enable, lot, TP, cân bằng).

### 2.1 Common (Magic & Comment)

- **Magic Number** – AA = magic này; BB = Magic + 1; CC = Magic + 2.
- **Order comment** – Comment chung cho mọi lệnh (ví dụ "EA Grid").
- **Cancel same-side when no opposite** – Khi giá cách base ít nhất N bậc và **không có lệnh phía bên kia**, xóa toàn bộ **lệnh chờ cùng phía** với giá và không đặt thêm lệnh chờ cùng phía.
- **Cancel same-side min levels from base** – Số bậc lưới tối thiểu (giá cách base) để áp dụng trên (ví dụ 5 = chỉ khi giá ≥ 5 bậc so với base).

### 2.2 AA (cài đặt)

- **Enable AA** – Bật/tắt AA (Buy Stop + Sell Stop).
- **Lot level 1** – Khối lượng cho bậc đầu tiên.
- **Fixed / Geometric** – Cách tính lot: Cố định hoặc Nhân (geometric theo bậc).
- **Lot multiplier** – Với Geometric: hệ số nhân cho bậc 2 trở lên.
- **Max lot** – Lot tối đa mỗi lệnh (0 = không giới hạn).
- **Take profit (pips)** – TP theo pips (0 = tắt).
- **Enable Balance** – Dùng pool để cắt lệnh AA lỗ.
- **Threshold (USD)** – Cắt khi (pool + lỗ) ≥ ngưỡng và ≥ 0.
- **Cooldown (giây)** – Thời gian chờ sau khi cắt (0 = không).

**Quy tắc cân bằng (AA + BB + CC)**

- **Quy tắc 1 – Ngược phía:** Chỉ đóng lệnh âm ở **phía ngược với giá hiện tại qua đường gốc**: giá trên base → đóng Sell (dưới base); giá dưới base → đóng Buy (trên base).
- **Khóa Buy / Khóa Sell (tránh đóng nhầm):** Khi **giá trên đường gốc** thì **khóa lệnh Buy** – cân bằng **không được** đóng bất kỳ lệnh Buy nào. Khi **giá dưới đường gốc** thì **khóa lệnh Sell** – cân bằng **không được** đóng bất kỳ lệnh Sell nào.
- **Quy tắc 2 – Xa trước:** Đóng lệnh âm **xa đường gốc trước**, rồi đến gần. Cùng bậc: **AA → BB → CC**.
- Mỗi loại (AA, BB, CC) dùng **ngưỡng riêng** khi kiểm tra (Pool + lỗ) ≥ ngưỡng. Pool chung; **giá hiện tại** phải cách đường gốc **ít nhất 5 bậc lưới**; cooldown sau khi đóng.
- **Nếu pool không đủ đóng hết** lệnh xa nhất: EA **đóng một phần** (lot tỷ lệ với số $ có thể dùng). Lệnh đóng do cân bằng (full hoặc partial) có comment deal **"Balance order"**.

### 2.3 BB (cài đặt)

- Cấu trúc giống AA: Enable, lot, Fixed/Geometric, hệ số nhân, max lot, Take profit, Enable Balance, Threshold (USD), Cooldown (giây). Cân bằng dùng logic thống nhất (xa nhất trước, cùng bậc: AA → BB → CC).

### 2.4 CC (cài đặt)

- Logic giống BB, tham số riêng: Enable, lot, Fixed/Geometric, hệ số nhân, max lot, Take profit, Enable Balance, Threshold (USD), Cooldown (giây). Cân bằng dùng logic thống nhất (xa nhất trước, cùng bậc: AA → BB → CC).

---

## 3. SESSION: Trailing profit (Gồng lãi)

- **Enable trailing** – Khi lãi lệnh đang mở (phiên hiện tại) ≥ ngưỡng (USD), hủy toàn bộ lệnh chờ và bắt đầu gồng lãi SL (Buy/Sell) trên lệnh đang mở.
- **Start trailing when open profit ≥ (USD)** – Ngưỡng để vào chế độ gồng lãi.
- **Lock: close all when profit drops this % from peak** – Nếu lãi giảm từ đỉnh phiên đúng bằng % này thì đóng hết và reset (phiên mới).
- **Pips: SL distance / trailing step** – Khoảng cách SL so với giá và bước cập nhật gồng lãi.

Chỉ lệnh mở trong **phiên hiện tại** mới dùng cho gồng lãi. Thông báo gửi khi reset.

**Vẽ trên biểu đồ:**
- **Đường gốc mảnh** – Đường ngang tại giá base (cập nhật khi EA reset).
- **Đường dọc thời gian** – Thời điểm phiên bắt đầu (EA khởi động hoặc reset). Cập nhật mỗi lần EA reset.

---

## 4. CAPITAL % SCALING (Scale theo % vốn)

- **Scale by capital growth** – Khi bật, **lot** (AA/BB/CC) và **ngưỡng gồng lãi (USD)** được nhân theo % tăng vốn so với **vốn cơ sở**.
- **Base capital (USD)** – 0 = dùng balance khi gắn EA; > 0 = dùng giá trị này. Vốn cơ sở chỉ dùng cho scale lot/TP/SL/Trailing. Cập nhật khi EA reset (đầu phiên).
- **x% (max 100)** – Hệ số scale. Công thức: `multiplier = 1 + growth × (x/100)`. TP/SL (pips) dùng giá trị input, không scale.
- **Max increase % for lot/functions** – Giới hạn tăng tối đa của lot và các hàm số (0 = không giới hạn). Ví dụ 100 = lot/hàm số tăng tối đa 100%, multiplier tối đa 2.0.

**Lưu ý:** Vốn cơ sở chỉ dùng cho scale (lot, TP, SL, trailing). "Initial balance at EA startup" và "Change vs initial capital at EA startup" dùng **vốn lúc EA attach lần đầu** (không reset), không dùng vốn cơ sở.

---

## 5. NOTIFICATIONS (Thông báo)

- **Send notification when EA resets or stops** – Gửi thông báo khi reset toàn bộ hoặc dừng EA. Nội dung gồm lý do, chart, balance, **Change vs initial capital at EA startup** (%), drawdown tối đa, lot tối đa / tổng lệnh mở. Khi dùng khóa lãi, tin reset có dòng **Locked profit (saved, cumulative): X.XX USD**.
- **Initial balance at EA startup** – Vốn khi EA attach lần đầu. **Không reset** (giữ nguyên dù EA reset nhiều lần).
- **Change vs initial capital at EA startup** – % = (vốn hiện tại − vốn lúc attach) / vốn lúc attach × 100. Tính theo vốn lúc EA attach lần đầu, không theo vốn cơ sở.

**Telegram:**
- **Enable Telegram** – Gửi thông báo lên nhóm Telegram qua Bot.
- **Bot Token** – Token từ @BotFather.
- **Chat ID** – ID nhóm (số âm, ví dụ: -1001234567890).
- **Lưu ý:** Vào Tools → Options → Expert Advisors → Allow WebRequest for listed URL, thêm: `https://api.telegram.org`

**Ví dụ (thông báo MT5 & Telegram – nội dung giống nhau):**

```
EA RESET
Chart: GBPUSD
Reason: EA stopped (reason: 1)

--- SETTINGS ---
Initial balance at EA startup: 50000.00 USD
Base capital (USD): 50000.00
Capital scale %: 50.0%

--- CURRENT STATUS ---
Current balance: 24800.00 USD
Change vs initial capital at EA startup: -50.40%
Max drawdown: 320.00 USD
Lowest balance (since attach): 24680.00 USD
Locked profit (saved, cumulative): 125.50 USD

--- FREE EA ---
Free MT5 automated trading EA.
Just register an account using this link: https://one.exnessonelink.com/a/iu0hffnbzb
After registering, send me your account ID to receive the EA.
```

---

## 6. LOCK PROFIT (Khóa lãi – % tiền tiết kiệm)

**Ý nghĩa:** Khóa lãi = dự trữ một **phần trăm** mỗi lần **đóng lệnh có lãi tại TP**. Số tiền lock **cộng dồn qua các phiên, không reset**. Số $ lock đó **không dùng cho cân bằng** (sàn bảo vệ phần này).

Khi bật:

- Mỗi lần đóng lệnh **có lãi** và **đóng bởi TP**, một **phần trăm** lợi nhuận đó được **khóa** vào quỹ. **Tiền lock cộng dồn qua mọi phiên, không reset** (kể cả khi EA reset hoặc phiên mới).
- **P/L deal** = Profit + Swap + Commission. Phần khóa = P/L deal × (Lock % / 100). Chỉ **phần còn lại** mới cộng vào pool **phiên hiện tại**.
- **Pool** = **chỉ lệnh đạt TP trong phiên hiện tại** trừ **lock trong phiên hiện tại**. Một pool chung cho cân bằng AA, BB, CC. **Số $ lock (tiết kiệm) không dùng cho cân bằng**.
- **Sàn vốn:** Khi cân bằng, chỉ đóng lệnh lỗ nếu **balance sau khi đóng ≥ vốn đầu phiên + tiền tiết kiệm đã khóa**. Phần lock cộng dồn không bao giờ bị tiêu.

**Tham số:**

- **Enable Lock Profit** – Bật/tắt tính năng.
- **Lock this %** – Phần trăm mỗi lần đóng lệnh có lãi (TP) để dự trữ (0–100). Ví dụ: 10 = khóa 10 USD từ 100 USD lãi; 90 USD vào pool cân bằng.

**Ví dụ (10% tiết kiệm, sàn vốn):**

- EA reset; **vốn đầu phiên = 1700 USD**. % tiết kiệm = 10%.
- **Lệnh 1, 2, 3** đạt TP: tổng lãi **+300 USD** → 10% khóa = **30 USD** → **270 USD** vào pool cân bằng.
- Balance = 2000 USD. **Sàn = 1700 + 30 = 1730 USD** (vốn không được giảm thấp hơn).
- **Lệnh 4, 5, 6** đang âm. EA chỉ được đóng khi:
  - (Pool + lỗ đó) ≥ ngưỡng và ≥ 0 (pool đủ bù lỗ),
  - **Balance sau khi đóng ≥ 1730 USD** (tổng lỗ tối đa trừ từ balance = 270 USD).
- Vậy vốn chỉ giảm tối thiểu đến **1730 USD**, không thấp hơn. Đợi thêm lệnh đạt TP thì pool tăng, cân bằng tiếp.

---

## Phiên và cách tính P/L

- **Phiên hiện tại** bắt đầu khi **gắn EA** hoặc EA **reset** (gồng lãi lock hoặc đóng hết).
- **Chỉ lệnh đóng bởi TP** (DEAL_REASON_TP) mới tính vào pool cân bằng. Đóng bởi SL / cắt tay / stop out **không** cộng pool.
- **Pool** = **TP trong phiên hiện tại** trừ **lock trong phiên hiện tại**. Tiền lock cộng dồn, không reset; không dùng cho cân bằng. Một pool chung cho AA, BB, CC.
- **Quy tắc cân bằng:** Cân bằng chỉ chạy khi **giá hiện tại** cách đường gốc **ít nhất 5 bậc lưới**. Chỉ đóng lệnh **lỗ** ở **phía đối diện** (giá trên base → đóng Sell dưới base; giá dưới base → đóng Buy trên base). **Khóa:** Giá trên base thì **khóa Buy** (không đóng Buy); giá dưới base thì **khóa Sell** (không đóng Sell). Đóng lệnh lỗ khi:
  1. **(Pool + lỗ đó) ≥ ngưỡng** và **≥ 0** (số $ lệnh đạt TP − % tiền tiết kiệm trong phiên đủ bù lỗ).
  2. **Balance sau khi đóng ≥ vốn đầu phiên + tiền tiết kiệm đã khóa** (sàn).
- **Thứ tự đóng:** Gom AA, BB, CC (chỉ lệnh lỗ ngược phía, tuân khóa Buy/Sell); ưu tiên **lệnh âm xa đường gốc trước**. Cùng bậc thì **AA → BB → CC**. Đóng hết bậc xa rồi đến bậc gần. Nếu pool không đủ đóng hết lệnh đó thì đóng **một phần** (lot theo tỷ lệ $); nếu không đủ min lot thì đợi pool tăng. Lệnh đóng do cân bằng có comment deal **"Balance order"**.
- **Pool còn lại** giảm khi đóng từng lệnh lỗ (theo thứ tự thống nhất: xa nhất trước, cùng bậc thì AA → BB → CC).
- **P/L lệnh đang mở** = Profit + Swap. Chỉ lệnh mở từ đầu phiên trở đi mới tính cho cân bằng và gồng lãi.

---

## Ví dụ phương pháp cân bằng

**Giả sử:** Đường gốc = 1000. Grid distance = 100 pips. Các bậc trên base: 1010, 1020, 1030, …; dưới base: 990, 980, 970, …

**Tình huống 1 – Giá trên base, cắt Sell dưới base (AA, BB, CC gộp chung)**

- Giá hiện tại = **1200** (cách base ≥ 5 bậc) → cân bằng được phép chạy.
- Lệnh đang mở: Buy 1010 (+lãi), **Sell CC 940 (−120 USD)**, **Sell BB 970 (−80 USD)**, **Sell AA 990 (−50 USD)**.
- **Đối diện + khóa:** Giá trên base → chỉ cắt **Sell dưới base**; **Buy bị khóa** (cân bằng không được đóng bất kỳ Buy nào).
- **Thứ tự đóng (xa nhất trước):** Cắt **Sell CC 940** trước, rồi Sell BB 970, rồi Sell AA 990. Deal có comment **"Balance order"**.

**Tình huống 2 – Giá dưới base, cắt Buy trên base**

- Giá hiện tại = **850** (cách base ≥ 5 bậc) → cân bằng được phép chạy.
- Lệnh đang mở: Sell 980 (+lãi), **Buy 1050 (−80 USD)**, **Buy 1100 (−150 USD)**.
- **Đối diện + khóa:** Giá dưới base → chỉ cắt **Buy trên base** (1050, 1100); **Sell bị khóa** (cân bằng không được đóng bất kỳ Sell nào).
- **Thứ tự đóng:** Xa đường gốc trước → cắt **Buy 1100** (−150 USD) trước. Deal có comment **"Balance order"**.

**Tình huống 3 – Pool không đủ, đóng một phần**

- Pool = 60 USD. Lệnh xa nhất cần cắt: Sell 940, lỗ 120 USD.
- Pool không đủ đóng hết → EA **đóng một phần** Sell 940: lot đóng tỷ lệ 60/120 = 50% lot.
- Lỗ thực tế khi đóng = 60 USD; pool còn lại = 0. Lệnh còn lại chờ pool tăng rồi đóng tiếp.

**Tình huống 4 – Cùng bậc xa nhất: ưu tiên AA → BB → CC**

- Lệnh cùng bậc 940: **Sell AA 940**, **Sell BB 940**, **Sell CC 940**.
- **Thứ tự đóng:** AA trước → BB → CC cuối. Vì cùng bậc nên ưu tiên theo loại.

**Tình huống 5 – Giá gần base, không cân bằng**

- Giá hiện tại = **1005** (chưa đủ 5 bậc từ base) → **cân bằng không chạy**, dù có lệnh lỗ.

---

## File

- **AdvancedGridTrading.mq5** – Một file EA; gắn vào chart trong MetaTrader 5.

---

## Phiên bản

2.06 – Advanced Grid Trading EA (Pro). AA, BB, CC; đặt lệnh từ bậc gần giá gốc ra xa; quy tắc cân bằng (ngược phía, xa trước; **khóa Buy khi giá trên gốc, khóa Sell khi giá dưới gốc** để tránh đóng nhầm); đóng lệnh cân bằng có comment **"Balance order"**; pool = **TP trong phiên trừ lock trong phiên**; **tiền lock cộng dồn qua các phiên, không reset, không dùng cho cân bằng**; tùy chọn hủy lệnh chờ cùng phía khi không có lệnh phía bên kia (số bậc cấu hình); mỗi bậc tối đa 1 lệnh mỗi loại; pool chung; cân bằng thống nhất (xa nhất trước, cùng bậc: AA → BB → CC, đóng một phần nếu pool không đủ); Max scale increase %; biểu đồ: đường gốc mảnh + đường dọc thời gian phiên; gồng lãi; thông báo Telegram; Initial balance at EA startup không reset.
