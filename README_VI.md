# Advanced Grid Trading EA

Expert Advisor MetaTrader 5 giao dịch lưới với **bốn** loại lệnh (**AA, BB, CC, DD**), gồng lãi, **cân bằng** theo phiên (**chỉ AA/BB/CC**), scale vốn, **khóa lãi** (% tiết kiệm mỗi TP kể cả DD), và thông báo (có **giá lúc reset**).

---

## Mục lục

1. [Tổng quan](#1-tổng-quan)  
2. [Input mặc định](#2-input-mặc-định-tóm-tắt)  
3. [Lưới & vị trí lệnh](#3-lưới--vị-trí-lệnh)  
4. [So sánh AA/BB/CC với DD](#4-so-sánh-aabbcc-với-dd)  
5. [Pool & khóa lãi](#5-pool--khóa-lãi)  
6. [Ví dụ cân bằng](#6-ví-dụ-cân-bằng)  
7. [Phiên gồng lãi](#7-phiên-gồng-lãi)  
8. [Ví dụ thông báo đầy đủ](#8-ví-dụ-thông-báo-đầy-đủ)  
9. [File & phiên bản](#9-file--phiên-bản)

---

## 1. Tổng quan

- **Phiên** bắt đầu khi gắn EA hoặc khi EA **reset** (gồng lock, breakeven, v.v.). Chỉ deal **trong phiên hiện tại** mới tính cho cân bằng và gồng lãi.
- **Chỉ lệnh đóng bởi TP** mới cộng vào **pool cân bằng**. Đóng bởi SL / tay / stop out **không** vào pool.
- **Pool** (mỗi phiên) = tổng **lãi TP − phần lock** trong phiên. TP từ **AA, BB, CC và DD** đều làm đầy pool. Pool **chỉ dùng để đóng lệnh lỗ AA/BB/CC**. **DD không bao giờ bị đóng để cân bằng.**
- **Tiền tiết kiệm (lock):** mỗi lần chốt lãi bằng TP (AA/BB/CC/**DD**) trích một **%** vào quỹ; **cộng dồn, không reset**. Phần lock **không bị tiêu** khi cân bằng (có **sàn** bảo vệ).
- **Magic:** AA = Magic nhập vào; BB = +1; CC = +2; **DD = +3**. Một **comment** chung (vd. `EA Grid`).

---

## 2. Input mặc định (tóm tắt)

| Nhóm | Tham số | Mặc định |
|------|---------|----------|
| **GRID** | Grid distance (pips) | 2000 |
| | Max grid levels per side | **40** |
| **DD** | Lot level 1 | **0.01** |
| | Fixed / Geometric | **Fixed** |
| | TP (pips) | 2000 |
| **Gồng lãi** | Ngưỡng lãi mở (USD) | **200** |
| | Chế độ khi lãi giảm | Return to initial |
| | Point A / Bước (pips) | 1500 / 1000 |
| **Vốn** | Base capital (USD) | **100000** (0 = balance lúc attach) |
| **Lock** | % lock | 25 |

*(Giá trị chính xác nằm trong input của file `AdvancedGridTrading.mq5`.)*

---

## 3. Lưới & vị trí lệnh

- **Đường gốc** = giá khi bắt đầu phiên. Các bậc cách nhau **Grid distance**. **Max grid levels** = số bậc mỗi phía trên/dưới gốc.
- **AA / BB / CC (Stop):**
  - **Buy Stop:** chỉ bậc **trên gốc** và **trên giá hiện tại** (giá phải lên mới khớp).
  - **Sell Stop:** chỉ bậc **dưới gốc** và **dưới giá hiện tại** (giá phải xuống mới khớp).
- **DD (Limit):**
  - **Sell Limit** ở bậc **trên gốc** (giá **xuống** chạm mức → bán khớp).
  - **Buy Limit** ở bậc **dưới gốc** (giá **lên** chạm mức → mua khớp).
- EA đặt/bổ sung lệnh **từ bậc gần gốc ra xa**. Mỗi bậc tối đa **một** pending mỗi loại (trùng thì xóa thừa).

---

## 4. So sánh AA/BB/CC với DD

| | AA, BB, CC | DD |
|--|------------|-----|
| **Loại lệnh** | Buy Stop / Sell Stop | Sell Limit (trên gốc) / Buy Limit (dưới gốc) |
| **Cân bằng** | Có (từng loại bật/tắt) | **Không** – không đóng DD để cân bằng |
| **Pool** | TP vào pool | **TP DD cũng vào pool** (nuôi cân bằng AA/BB/CC) |
| **Khóa lãi** | Có | **Có** – cùng % với các loại khác |
| **Scale lot** | Có | **Có** – cùng hệ số session |

---

## 5. Pool & khóa lãi

**Hằng số trong code (không phải input):**

- Cân bằng khi **(pool + lỗ lệnh đó) ≥ 20 USD**
- **Cooldown 300 giây** sau mỗi lần đóng cân bằng
- **Chuẩn bị:** giá cách gốc **≥ 3 bậc** → chọn lệnh lỗ **xa nhất** phía **đối diện** (pending có thêm `| BP` trong comment; position đánh dấu trên chart). **Chỉ khi giá qua đường gốc** mới bỏ chuẩn bị (không bỏ chỉ vì lùi trong 3 bậc cùng phía).
- **Thực hiện đóng:** giá **≥ 5 bậc** khỏi gốc **và** pool đủ → đóng hết hoặc **một phần**. Comment deal **"Balance order"**.

**Ví dụ khóa 25%:**

- Chốt TP +100 USD → khóa 25 USD → **75 USD** vào pool phiên.
- Sàn khi cân bằng: balance sau đóng phải **≥ vốn đầu phiên + tổng đã khóa** (tiết kiệm không bị trừ hết).

---

## 6. Ví dụ cân bằng

**Giả sử:** Đường gốc = 1000; bước lưới 100 pips → trên: 1010, 1020, … dưới: 990, 980, …

**Ví dụ 1 – Giá trên gốc, cắt Sell dưới gốc**

- Giá = **1200** (≥ 5 bậc) → được phép cân bằng.
- Có Buy lãi; có **Sell** dưới gốc đang lỗ.
- Trên gốc → chỉ đóng **Sell** dưới gốc; **Buy bị khóa** (không đóng Buy).
- Thứ tự: **xa đường gốc trước**; cùng bậc thì **AA → BB → CC**.

**Ví dụ 2 – Giá dưới gốc, cắt Buy trên gốc**

- Chỉ đóng **Buy** trên gốc; **Sell bị khóa**.

**Ví dụ 3 – Pool không đủ → đóng một phần**

- Pool 60 USD, lệnh cần cắt lỗ 120 USD → đóng **50%** lot; đợi thêm TP rồi cắt tiếp.

**Ví dụ 4 – Cùng bậc: ưu tiên AA → BB → CC**

**Ví dụ 5 – Giá gần gốc (&lt; 5 bậc)**

- **Không** thực hiện đóng cân bằng.

**DD:** lệnh DD lỗ **không** bị đóng để cân bằng; TP DD **vẫn nạp pool** cho AA/BB/CC.

---

## 7. Phiên gồng lãi

- Khi **lãi lệnh mở ≥ ngưỡng** (mặc định **200 USD**), EA hủy pending và gồng SL (Point A / bước theo input).
- **Lock profit:** lãi giảm X% từ đỉnh → đóng hết + reset phiên.
- **Return:** lãi giảm X% → thoát gồng, đặt lại pending, không ép đóng.
- **Breakeven reset** (tùy chọn): bật thì có thể reset khi đủ điều kiện bậc + P/L.

---

## 8. Ví dụ thông báo đầy đủ

Khi reset/dừng EA, tin nhắn (MT5 + Telegram nếu bật) có dạng:

```
EA RESET
Chart: GBPUSD
Reason: Trailing profit (SL hit)
Price at reset: 1.26543

--- SETTINGS ---
Initial balance at EA startup: 100000.00 USD
Base capital (USD): 100000.00
Capital scale %: 50.0%

--- CURRENT STATUS ---
Current balance: 102500.00 USD
Change vs initial capital at EA startup: +2.50%
Max drawdown: 150.00 USD
Lowest balance (since attach): 99850.00 USD
Locked profit (saved, cumulative): 125.50 USD

--- FREE EA ---
...
```

**Telegram:** thêm `https://api.telegram.org` vào **Tools → Options → Expert Advisors → Allow WebRequest**.

---

## 9. File & phiên bản

- **AdvancedGridTrading.mq5** – một file EA, gắn vào chart MT5.
- **Phiên bản 2.07** – AA/BB/CC (Stop) + **DD** (Limit trên/dưới gốc); pool gồm TP cả bốn loại; cân bằng **chỉ** AA/BB/CC; khóa lãi mọi TP; thông báo reset có **Price at reset**.
