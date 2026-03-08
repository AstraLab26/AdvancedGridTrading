# Advanced Grid Trading EA

Expert Advisor MetaTrader 5 giao dịch lưới với ba loại lệnh độc lập (AA, BB, CC), gồng lãi (trailing profit), logic cân bằng theo phiên, scale theo vốn, khóa lãi (% tiền tiết kiệm) và thông báo.

---

## Tổng quan

- **Grid (Lưới):** Giá cơ sở khi gắn EA, các bậc cách đều (pips), số bậc tối đa mỗi bên. **Buy Stop** chỉ đặt ở bậc **trên đường gốc và trên giá hiện tại**; **Sell Stop** chỉ đặt ở bậc **dưới đường gốc và dưới giá hiện tại**. Bậc nào thiếu lệnh (theo loại AA/BB/CC đang bật) thì EA bổ sung.
- **AA, BB & CC:** Lot, Fixed/Geometric, hệ số nhân, lot tối đa, TP và magic riêng. Cùng một lưới; **mỗi bậc tối đa 1 lệnh mỗi loại** (theo input: bật AA thì tối đa 1 AA, bật BB thì 1 BB, bật CC thì 1 CC). AA = Magic Number, BB = Magic Number + 1, CC = Magic Number + 2. Tất cả lệnh dùng chung một comment (ví dụ "EA Grid").
- **Phiên (Session):** Phiên hiện tại bắt đầu khi gắn EA hoặc khi EA thực hiện reset tự động. Mọi logic cân bằng và gồng lãi chỉ dùng lệnh đóng và P/L đóng trong phiên hiện tại. **Chỉ lệnh đóng bởi Take Profit (TP)** mới cộng vào pool cân bằng; đóng bởi SL hoặc cắt tay không tính.
- **Pool cân bằng:** Pool = tổng **(AA + BB + CC) đóng TP trong phiên** trừ **% tiền tiết kiệm (lock %)**. Một pool chung dùng để cân bằng lệnh AA, BB, CC đang lỗ. Cân bằng chỉ được thực hiện khi **pool đủ bù lỗ** và **balance sau khi đóng không thấp hơn sàn** (vốn đầu phiên + tiền tiết kiệm đã khóa).

---

## 1. GRID (LƯỚI)

| Tham số | Mô tả |
|--------|--------|
| **Grid distance (pips)** | Khoảng cách giữa hai bậc lưới liền kề. |
| **Max grid levels per side** | Số bậc tối đa phía trên và phía dưới đường cơ sở. |

Các bậc cách đều. Không đặt lệnh tại đường cơ sở; bậc 1 gần đường cơ sở nhất, rồi bậc 2, 3, …  
**Vị trí lệnh chờ:** Buy Stop tại bậc **trên đường gốc và trên giá hiện tại**; Sell Stop tại bậc **dưới đường gốc và dưới giá hiện tại**. Mỗi bậc tối đa 1 AA, 1 BB, 1 CC (theo loại đang bật); thiếu thì EA bổ sung.

---

## 2. ORDERS (LỆNH)

### 2.1 AA (cài đặt)

- **Enable AA** – Bật/tắt AA (Buy Stop + Sell Stop).
- **Lot level 1** – Khối lượng cho bậc đầu tiên.
- **Fixed / Geometric** – Cách tính lot: Cố định hoặc Nhân (geometric theo bậc).
- **Lot multiplier** – Với Geometric: hệ số nhân cho bậc 2 trở lên.
- **Max lot** – Lot tối đa mỗi lệnh (0 = không giới hạn).
- **Take profit (pips)** – TP theo pips (0 = tắt).

**Cân bằng AA (bởi pool lệnh đóng TP)**

- Ưu tiên **đóng lệnh AA đang lỗ xa đường gốc trước** (một lệnh mỗi lần). Đóng **một lệnh AA đang lỗ** (phía ngược) khi:
  1. **(Pool + lỗ AA đó) ≥ ngưỡng** (USD) và **≥ 0** (pool đủ bù lỗ).
  2. **Balance sau khi đóng ≥ sàn** (vốn đầu phiên + tiền tiết kiệm đã khóa).
- **Nếu pool không đủ đóng hết** lệnh âm xa nhất: EA **đóng một phần** (lot tỷ lệ với số $ có thể dùng). Nếu không đủ cho tối thiểu một phần (min lot) thì đợi pool tăng rồi đóng sau.
- Pool = **lệnh đóng TP** (AA+BB+CC) trong phiên trừ % tiết kiệm. Chỉ trong phiên; giá phải cách đường cơ sở **5 bậc**; cooldown sau khi đóng.

### 2.2 Common (Magic & Comment)

- **Magic Number** – AA dùng magic này; BB = Magic + 1; CC = Magic + 2.
- **Order comment** – Comment chung cho mọi lệnh (ví dụ "EA Grid").

### 2.3 BB (cài đặt)

- Cấu trúc giống AA: Enable, lot, Fixed/Geometric, hệ số nhân, max lot, Take profit.

**Cân bằng BB (bởi pool lệnh đóng TP)**

- Đóng **lệnh BB đang lỗ** (phía ngược) khi (pool + lỗ đó) ≥ ngưỡng và ≥ 0, và **balance sau khi đóng ≥ sàn**. Ưu tiên **đóng lệnh âm xa đường gốc trước**. Nếu pool không đủ đóng hết lệnh xa nhất thì **đóng một phần** (lot tỷ lệ); không đủ min lot thì đợi pool tăng. Pool chung (TP đóng − lock %). Chỉ trong phiên; giá cách đường cơ sở **5 bậc**; cooldown.

### 2.4 CC (cài đặt)

- Logic giống BB, tham số riêng: Enable, lot, Fixed/Geometric, hệ số nhân, max lot, Take profit.

**Cân bằng CC (bởi pool lệnh đóng TP)**

- Đóng **lệnh CC đang lỗ** (phía ngược) khi (pool + lỗ đó) ≥ ngưỡng và ≥ 0, và **balance sau khi đóng ≥ sàn**. Ưu tiên **đóng lệnh âm xa đường gốc trước**. Nếu pool không đủ đóng hết lệnh xa nhất thì **đóng một phần** (lot tỷ lệ); không đủ min lot thì đợi pool tăng. Cùng pool chung. Chỉ trong phiên; cooldown.

---

## 3. SESSION: Trailing profit (Gồng lãi)

- **Enable trailing** – Khi lãi lệnh đang mở (phiên hiện tại) ≥ ngưỡng (USD), hủy toàn bộ lệnh chờ và bắt đầu gồng lãi SL (Buy/Sell) trên lệnh đang mở.
- **Start trailing when open profit ≥ (USD)** – Ngưỡng để vào chế độ gồng lãi.
- **Lock: close all when profit drops this % from peak** – Nếu lãi giảm từ đỉnh phiên đúng bằng % này thì đóng hết và reset (phiên mới).
- **Pips: SL distance / trailing step** – Khoảng cách SL so với giá và bước cập nhật gồng lãi.

Chỉ lệnh mở trong **phiên hiện tại** mới dùng cho gồng lãi. Thông báo gửi khi reset.

---

## 4. CAPITAL % SCALING (Scale theo % vốn)

- **Scale by capital growth** – Khi bật, **lot** (AA/BB/CC) và **ngưỡng gồng lãi (USD)** được nhân theo % tăng vốn so với vốn cơ sở.
- **Base capital (USD)** – 0 = dùng balance khi gắn EA; > 0 = dùng giá trị này. Vốn cơ sở cập nhật khi EA reset (đầu phiên).
- **x% (max 100)** – Hệ số scale. Công thức: `multiplier = 1 + growth × (x/100)`. TP/SL (pips) dùng giá trị input, không scale.

---

## 5. NOTIFICATIONS (Thông báo)

- **Send notification when EA resets or stops** – Gửi thông báo khi reset toàn bộ hoặc dừng EA. Nội dung gồm lý do, chart, balance, %, drawdown tối đa, lot tối đa / tổng lệnh mở. Khi dùng khóa lãi, tin reset có dòng **Locked profit (saved, cumulative): X.XX USD**.

---

## 6. LOCK PROFIT (Khóa lãi – % tiền tiết kiệm)

**Ý nghĩa:** Khóa lãi = dự trữ một **phần trăm** mỗi lần **đóng lệnh có lãi tại TP**. Số tiền khóa **không** đưa vào pool cân bằng. Chỉ **phần còn lại** (số $ lệnh đạt TP − % tiết kiệm) mới vào pool để chi cho cân bằng lệnh lỗ.

Khi bật:

- Mỗi lần đóng lệnh **có lãi** và **đóng bởi TP**, một **phần trăm** lợi nhuận đó (ví dụ 10%) được **khóa** vào quỹ tiết kiệm.
- **P/L deal** = Profit + Swap + Commission. Phần khóa = P/L deal × (Lock % / 100). Chỉ **phần còn lại** mới cộng vào pool cân bằng.
- **Pool cân bằng** = tổng trong phiên (lệnh đạt TP $ − lock %) cho AA, BB, CC. Một pool chung cho cân bằng AA, BB, CC.
- **Sàn vốn:** Khi cân bằng, chỉ đóng lệnh lỗ nếu **balance sau khi đóng ≥ vốn đầu phiên + tiền tiết kiệm đã khóa**. Vốn không được giảm thấp hơn sàn.

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
- **Pool** = (AA + BB + CC) đóng TP trong phiên, trừ lock % trên mỗi lệnh đóng TP có lãi. Một pool chung cho cân bằng AA, BB, CC.
- **Quy tắc cân bằng:** Chỉ đóng lệnh lỗ khi:
  1. **(Pool + lỗ đó) ≥ ngưỡng** và **≥ 0** (số $ lệnh đạt TP − % tiền tiết kiệm trong phiên đủ bù lỗ).
  2. **Balance sau khi đóng ≥ vốn đầu phiên + tiền tiết kiệm đã khóa** (sàn).
- **Thứ tự đóng:** Ưu tiên **lệnh âm xa đường gốc trước**. Nếu pool không đủ đóng hết lệnh đó thì đóng **một phần** (lot theo tỷ lệ $); nếu không đủ min lot thì đợi pool tăng.
- **Pool còn lại** giảm khi đóng từng lệnh lỗ (cùng tick: AA rồi BB rồi CC dùng chung pool còn lại).
- **P/L lệnh đang mở** = Profit + Swap. Chỉ lệnh mở từ đầu phiên trở đi mới tính cho cân bằng và gồng lãi.

---

## File

- **AdvancedGridTrading.mq5** – Một file EA; gắn vào chart trong MetaTrader 5.

---

## Phiên bản

2.01 – Advanced Grid Trading EA (Pro). AA, BB, CC; Buy Stop trên đường gốc và trên giá, Sell Stop dưới đường gốc và dưới giá; mỗi bậc tối đa 1 lệnh mỗi loại, thiếu thì bổ sung; chỉ lệnh đóng TP cho pool; pool chung; sàn vốn = đầu phiên + tiền tiết kiệm; khóa lãi; scale theo vốn; cân bằng (ưu tiên lệnh âm xa đường gốc, đóng một phần nếu pool không đủ) và gồng lãi theo phiên.
