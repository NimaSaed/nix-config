// SPDX-License-Identifier: GPL-2.0
// Upstream LKML patch v3 by Andrew Maney <andrewmaney05@gmail.com>
// "[PATCH v3] HID: Expose LattePanda IOTA UPS as a power_supply device"
// https://lkml.iu.edu/hypermail/linux/kernel/2605.2/12097.html
//
// Local additions vs. upstream:
//   - ENERGY_FULL_DESIGN / ENERGY_FULL / ENERGY_NOW derived from capacity %
//     so that UPower has a non-zero energy baseline to work from.
//   - POWER_NOW estimated from the UPS's 1% capacity steps. The device only
//     reports a whole percent (its HID descriptor has no voltage, current or
//     runtime usage), and that percent is lumpy: it can sit still for 20 min
//     and then drop 2% in 3 min. Rating from two consecutive steps therefore
//     swings by an order of magnitude. Instead the driver keeps a ring of
//     timestamped capacity samples and, at read time, averages over a window
//     that spans at least rate_window_steps percent AND rate_window_ms of
//     elapsed time. Using the read time as the end of the window makes the
//     estimate decay smoothly during a plateau rather than freeze.
//   - energy_full_uwh module param lets you tune to your actual cell capacity.
//     Default: 3 × 3500mAh × 3.7V = 38,850,000 µWh. It scales the reported
//     watts but cancels out of UPower's time-to-empty.
//   - PresentStatus decoded per the descriptor's usage order (Charging bit 0,
//     Discharging bit 1, ACPresent bit 2, BatteryPresent bit 3, FullyCharged
//     bit 8). Upstream reads bit 0 as "plugged in" and bit 2 as "charging";
//     that works while charging because both bits are set, but at the 80%
//     DIP-switch cap the firmware clears Charging and sets FullyCharged, which
//     upstream would show as charging forever with AC offline.
//   - charge_limit module param mirrors the SW3 DIP switch position.
#include <linux/power_supply.h>
#include <linux/completion.h>
#include <linux/workqueue.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/spinlock.h>
#include <linux/math64.h>
#include <linux/minmax.h>
#include <linux/limits.h>
#include <linux/ktime.h>
#include <linux/hid.h>
#include <linux/usb.h>

#define USB_VENDOR_ID_LATTEPANDA_IOTA     0x2341
#define USB_DEVICE_ID_LATTEPANDA_IOTA_UPS 0x8036

#define REPORT_ID_CAPACITY 0x0C
#define REPORT_ID_STATUS   0x07

/*
 * PresentStatus (report 0x07) is a 16-bit little-endian bitfield laid out in
 * the order the HID descriptor declares its usages, which matches the
 * Arduino HIDPowerDevice library the firmware is built on. Observed while
 * discharging: 0x0a = DISCHARGING | BATTERY_PRESENT.
 */
#define STATUS_CHARGING            BIT(0)
#define STATUS_DISCHARGING         BIT(1)
#define STATUS_AC_PRESENT          BIT(2)
#define STATUS_BATTERY_PRESENT     BIT(3)
#define STATUS_BELOW_CAPACITY_LIMIT BIT(4)
#define STATUS_NEED_REPLACEMENT    BIT(6)
#define STATUS_FULLY_CHARGED       BIT(8)
#define STATUS_FULLY_DISCHARGED    BIT(9)

/* 3 × 3500mAh × 3.7V = 38,850,000 µWh */
#define ENERGY_FULL_DEFAULT_UWH 38850000

static unsigned int energy_full_uwh = ENERGY_FULL_DEFAULT_UWH;
module_param(energy_full_uwh, uint, 0444);
MODULE_PARM_DESC(energy_full_uwh,
	"Battery design capacity in µWh (default: 38850000 = 3×3500mAh@3.7V)");

/*
 * Rate window. Both bounds must be met (or the sample history exhausted):
 * at least this many 1% steps, and at least this much wall time. 6% is about
 * half an hour at this board's idle draw; 20 min covers the longest gauge
 * plateau seen. RATE_RING bounds how far back the window can reach.
 */
#define RATE_RING 16

static unsigned int rate_window_steps = 6;
module_param(rate_window_steps, uint, 0444);
MODULE_PARM_DESC(rate_window_steps,
	"Minimum number of 1% capacity steps averaged for POWER_NOW (default: 6)");

static unsigned int rate_window_ms = 20 * 60 * 1000;
module_param(rate_window_ms, uint, 0444);
MODULE_PARM_DESC(rate_window_ms,
	"Minimum time span averaged for POWER_NOW in ms (default: 1200000 = 20 min)");

/*
 * Where the board's SW3 DIP switch stops charging (80 or 100). The switch is
 * not readable over USB, so this mirrors its position. Only used to report
 * Full if the firmware does not raise FULLY_CHARGED at the cap. Also the
 * initial value of the writable charge_control_end_threshold attribute.
 */
static unsigned int charge_limit = 100;
module_param(charge_limit, uint, 0444);
MODULE_PARM_DESC(charge_limit,
	"Charge cap set by DIP switch SW3, 80 or 100 (default: 100)");

struct iota_ups_sample {
	ktime_t t;
	int cap;
};

MODULE_AUTHOR("Andrew Maney");
MODULE_DESCRIPTION("LattePanda IOTA UPS power supply driver");
MODULE_LICENSE("GPL");

struct iota_ups {
	struct power_supply_desc psu_desc;
	struct power_supply *psu;
	struct hid_device *hiddev;
	spinlock_t lock; /* Protects all cached values below */

	bool plugged_in;
	bool battery_present;
	char serial[64];
	int charge_limit;
	int psu_status;
	int capacity;

	/*
	 * Rate tracking: ring of (time, capacity) taken at every capacity
	 * change, plus one anchor sample at the start of a charge/discharge
	 * run. sample_head is the next slot to write.
	 */
	struct iota_ups_sample samples[RATE_RING];
	unsigned int sample_head;
	unsigned int sample_count;

	struct completion got_initial_data;
	struct work_struct register_work;
	bool got_capacity;
	bool data_ready;
	bool got_status;
};

static enum power_supply_property iota_ups_properties[] = {
	POWER_SUPPLY_PROP_CHARGE_CONTROL_END_THRESHOLD,
	POWER_SUPPLY_PROP_SERIAL_NUMBER,
	POWER_SUPPLY_PROP_MANUFACTURER,
	POWER_SUPPLY_PROP_MODEL_NAME,
	POWER_SUPPLY_PROP_TECHNOLOGY,
	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_ENERGY_FULL_DESIGN,
	POWER_SUPPLY_PROP_ENERGY_FULL,
	POWER_SUPPLY_PROP_ENERGY_NOW,
	POWER_SUPPLY_PROP_POWER_NOW,
	POWER_SUPPLY_PROP_PRESENT,
	POWER_SUPPLY_PROP_ONLINE,
	POWER_SUPPLY_PROP_STATUS,
	POWER_SUPPLY_PROP_SCOPE,
};

static const struct hid_device_id iota_ups_devices[] = {
	{ HID_USB_DEVICE(USB_VENDOR_ID_LATTEPANDA_IOTA,
			 USB_DEVICE_ID_LATTEPANDA_IOTA_UPS) },
	{ }
};
MODULE_DEVICE_TABLE(hid, iota_ups_devices);

/*
 * Estimate power (µW) over the recent capacity history. Called under
 * ups->lock. Walks back from the newest sample until the window contains at
 * least rate_window_steps steps and spans at least rate_window_ms, or the
 * history runs out. The window ends at the read time, not at the newest
 * step, so a long plateau lowers the estimate gradually instead of leaving a
 * stale value. That also biases the result low by the fraction of a percent
 * consumed since the last step, at most 1/rate_window_steps of the total.
 * Returns 0 (unknown) until at least rate_window_ms of history exists.
 */
static int iota_ups_power_now(struct iota_ups *ups)
{
	const struct iota_ups_sample *newest, *oldest;
	unsigned int steps_wanted, i;
	ktime_t now = ktime_get();
	u64 energy_uwh, power_uw;
	s64 span_ms;

	/* Need the anchor plus at least one step. */
	if (ups->sample_count < 2)
		return 0;

	steps_wanted = clamp(rate_window_steps, 1U, RATE_RING - 1);
	newest = &ups->samples[(ups->sample_head + RATE_RING - 1) % RATE_RING];
	oldest = newest;

	for (i = 1; i < ups->sample_count; i++) {
		oldest = &ups->samples[(ups->sample_head + RATE_RING - 1 - i) % RATE_RING];
		if (i >= steps_wanted &&
		    ktime_to_ms(ktime_sub(now, oldest->t)) >= rate_window_ms)
			break;
	}

	/*
	 * Too little history to say anything. The gauge sags several percent
	 * in the first minute after boot under load, so a rate from a short
	 * window is nonsense (observed: 54 W, 17 min remaining). Report 0,
	 * which UPower shows as unknown, until the window is long enough.
	 */
	span_ms = ktime_to_ms(ktime_sub(now, oldest->t));
	if (span_ms < (s64)rate_window_ms)
		return 0;

	/* µWh consumed across the window; ≤ energy_full_uwh, fits u64 × 3.6e6. */
	energy_uwh = div64_u64((u64)energy_full_uwh * abs(oldest->cap - newest->cap), 100);
	power_uw = div64_u64(energy_uwh * 3600000ULL, (u64)span_ms);

	return (int)min_t(u64, power_uw, INT_MAX);
}

static int iota_ups_get_property(struct power_supply *supply,
				 enum power_supply_property psp,
				 union power_supply_propval *val)
{
	struct iota_ups *ups = power_supply_get_drvdata(supply);
	unsigned long flags;

	spin_lock_irqsave(&ups->lock, flags);

	switch (psp) {
	case POWER_SUPPLY_PROP_STATUS:
		val->intval = ups->psu_status;
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		val->intval = ups->capacity;
		break;
	case POWER_SUPPLY_PROP_ENERGY_FULL_DESIGN:
	case POWER_SUPPLY_PROP_ENERGY_FULL:
		val->intval = energy_full_uwh;
		break;
	case POWER_SUPPLY_PROP_ENERGY_NOW:
		val->intval = (int)div64_u64((u64)energy_full_uwh * ups->capacity, 100);
		break;
	case POWER_SUPPLY_PROP_POWER_NOW:
		val->intval = iota_ups_power_now(ups);
		break;
	case POWER_SUPPLY_PROP_PRESENT:
		val->intval = ups->battery_present ? 1 : 0;
		break;
	case POWER_SUPPLY_PROP_ONLINE:
		val->intval = ups->plugged_in ? 1 : 0;
		break;
	case POWER_SUPPLY_PROP_SCOPE:
		val->intval = POWER_SUPPLY_SCOPE_SYSTEM;
		break;
	case POWER_SUPPLY_PROP_TECHNOLOGY:
		val->intval = POWER_SUPPLY_TECHNOLOGY_LION;
		break;
	case POWER_SUPPLY_PROP_CHARGE_CONTROL_END_THRESHOLD:
		val->intval = ups->charge_limit;
		break;
	case POWER_SUPPLY_PROP_MANUFACTURER:
		val->strval = "DFRobot";
		break;
	case POWER_SUPPLY_PROP_MODEL_NAME:
		val->strval = "LattePanda IOTA UPS";
		break;
	case POWER_SUPPLY_PROP_SERIAL_NUMBER:
		val->strval = ups->serial;
		break;
	default:
		spin_unlock_irqrestore(&ups->lock, flags);
		return -EINVAL;
	}

	spin_unlock_irqrestore(&ups->lock, flags);
	return 0;
}

static int iota_ups_set_property(struct power_supply *supply,
				 enum power_supply_property psp,
				 const union power_supply_propval *val)
{
	struct iota_ups *ups = power_supply_get_drvdata(supply);

	if (psp == POWER_SUPPLY_PROP_CHARGE_CONTROL_END_THRESHOLD) {
		unsigned long flags;

		if (val->intval != 80 && val->intval != 100)
			return -EINVAL;

		spin_lock_irqsave(&ups->lock, flags);
		ups->charge_limit = val->intval;
		spin_unlock_irqrestore(&ups->lock, flags);
		return 0;
	}

	return -EINVAL;
}

static int iota_ups_property_is_writable(struct power_supply *supply,
					 enum power_supply_property psp)
{
	return psp == POWER_SUPPLY_PROP_CHARGE_CONTROL_END_THRESHOLD;
}

/* Record a capacity sample. Called under ups->lock. */
static void iota_ups_push_sample(struct iota_ups *ups, int cap)
{
	ups->samples[ups->sample_head].t = ktime_get();
	ups->samples[ups->sample_head].cap = cap;
	ups->sample_head = (ups->sample_head + 1) % RATE_RING;
	if (ups->sample_count < RATE_RING)
		ups->sample_count++;
}

/* Forget the run so far and anchor a new one at the current capacity. */
static void iota_ups_reset_samples(struct iota_ups *ups)
{
	ups->sample_head = 0;
	ups->sample_count = 0;
	if (ups->got_capacity)
		iota_ups_push_sample(ups, ups->capacity);
}

static int iota_ups_raw_event(struct hid_device *hdev,
			      struct hid_report *report,
			      u8 *data, int size)
{
	struct iota_ups *ups = hid_get_drvdata(hdev);
	unsigned long flags;
	bool changed = false;

	if (size < 2)
		return 0;

	spin_lock_irqsave(&ups->lock, flags);

	switch (data[0]) {
	case REPORT_ID_STATUS: {
		u16 status = data[1] | (size > 2 ? data[2] << 8 : 0);
		bool plugged_in = !!(status & STATUS_AC_PRESENT);
		bool battery_present = !!(status & STATUS_BATTERY_PRESENT);
		int new_status;

		/*
		 * The board's SW3 DIP switch can stop charging at 80%. At the
		 * cap the firmware drops CHARGING and raises FULLY_CHARGED
		 * while AC stays present. Report that as Full, and also treat
		 * "AC present, not charging, at or above the configured limit"
		 * as Full in case the firmware only clears CHARGING.
		 */
		if (status & STATUS_FULLY_CHARGED) {
			new_status = POWER_SUPPLY_STATUS_FULL;
		} else if (status & STATUS_CHARGING) {
			if (ups->capacity >= ups->charge_limit)
				new_status = POWER_SUPPLY_STATUS_FULL;
			else
				new_status = POWER_SUPPLY_STATUS_CHARGING;
		} else if (status & STATUS_DISCHARGING) {
			new_status = POWER_SUPPLY_STATUS_DISCHARGING;
		} else if (plugged_in) {
			if (ups->capacity >= ups->charge_limit)
				new_status = POWER_SUPPLY_STATUS_FULL;
			else
				new_status = POWER_SUPPLY_STATUS_NOT_CHARGING;
		} else {
			new_status = POWER_SUPPLY_STATUS_UNKNOWN;
		}

		if (new_status != ups->psu_status ||
		    plugged_in != ups->plugged_in ||
		    battery_present != ups->battery_present) {
			/*
			 * Any status change starts a new run for the rate
			 * estimate: time spent sitting Full must not be counted
			 * against the first discharge step after unplugging.
			 * iota_ups_reset_samples() re-anchors at the current
			 * capacity, so the boot-time UNKNOWN→Discharging
			 * transition costs nothing.
			 */
			if (new_status != ups->psu_status)
				iota_ups_reset_samples(ups);

			ups->plugged_in = plugged_in;
			ups->battery_present = battery_present;
			ups->psu_status = new_status;
			changed = true;
		}

		ups->got_status = true;
		break;
	}

	case REPORT_ID_CAPACITY: {
		int new_cap = clamp((int)data[1], 0, 100);

		/*
		 * The very first report anchors the run even when it happens to
		 * equal the placeholder capacity, so the first real step is
		 * measured against it instead of becoming the anchor itself.
		 */
		if (!ups->got_capacity || new_cap != ups->capacity) {
			ups->capacity = new_cap;
			iota_ups_push_sample(ups, new_cap);
			changed = true;
		}

		ups->got_capacity = true;
		break;
	}
	}

	if (!ups->data_ready && ups->got_status && ups->got_capacity) {
		ups->data_ready = true;
		complete(&ups->got_initial_data);
	}

	spin_unlock_irqrestore(&ups->lock, flags);

	if (changed && ups->psu)
		power_supply_changed(ups->psu);

	return 0;
}

static void iota_ups_register_work(struct work_struct *work)
{
	struct iota_ups *ups = container_of(work, struct iota_ups, register_work);
	struct power_supply_config psu_config = {};
	struct power_supply *psu;

	wait_for_completion_timeout(&ups->got_initial_data, msecs_to_jiffies(3000));

	ups->psu_desc.name = devm_kasprintf(&ups->hiddev->dev, GFP_KERNEL,
					    "lattepanda-iota-ups.%s",
					    dev_name(&ups->hiddev->dev));
	if (!ups->psu_desc.name) {
		hid_err(ups->hiddev, "failed to allocate power supply name\n");
		return;
	}

	ups->psu_desc.property_is_writeable = iota_ups_property_is_writable;
	ups->psu_desc.num_properties = ARRAY_SIZE(iota_ups_properties);
	ups->psu_desc.get_property = iota_ups_get_property;
	ups->psu_desc.set_property = iota_ups_set_property;
	ups->psu_desc.properties = iota_ups_properties;
	ups->psu_desc.type = POWER_SUPPLY_TYPE_BATTERY;
	psu_config.drv_data = ups;

	psu = devm_power_supply_register(&ups->hiddev->dev, &ups->psu_desc, &psu_config);
	if (IS_ERR(psu)) {
		hid_err(ups->hiddev, "power supply registration failed: %pe\n", psu);
		return;
	}

	ups->psu = psu;
	power_supply_changed(ups->psu);
	hid_info(ups->hiddev, "LattePanda IOTA UPS registered as a power_supply device\n");
}

static int iota_ups_probe(struct hid_device *hdev,
			  const struct hid_device_id *id)
{
	struct iota_ups *ups;
	int ret;

	ups = devm_kzalloc(&hdev->dev, sizeof(*ups), GFP_KERNEL);
	if (!ups)
		return -ENOMEM;

	ups->hiddev = hdev;
	ups->psu_status = POWER_SUPPLY_STATUS_UNKNOWN;
	ups->capacity = 50;
	ups->battery_present = true;
	ups->charge_limit = (charge_limit == 80) ? 80 : 100;

	init_completion(&ups->got_initial_data);
	spin_lock_init(&ups->lock);
	hid_set_drvdata(hdev, ups);

	if (hid_is_usb(hdev)) {
		struct usb_device *udev = to_usb_device(hdev->dev.parent->parent);

		if (udev->serial)
			strscpy(ups->serial, udev->serial, sizeof(ups->serial));
		else
			strscpy(ups->serial, "Unknown", sizeof(ups->serial));
	} else {
		if (*hdev->uniq)
			strscpy(ups->serial, hdev->uniq, sizeof(ups->serial));
		else
			strscpy(ups->serial, "Unknown", sizeof(ups->serial));
	}

	ret = hid_parse(hdev);
	if (ret) {
		hid_err(hdev, "HID parse failed: %pe\n", ERR_PTR(ret));
		return ret;
	}

	ret = hid_hw_start(hdev, HID_CONNECT_HIDRAW);
	if (ret) {
		hid_err(hdev, "HID hw start failed: %pe\n", ERR_PTR(ret));
		return ret;
	}

	ret = hid_hw_open(hdev);
	if (ret) {
		hid_err(hdev, "HID hw open failed: %pe\n", ERR_PTR(ret));
		goto err_stop;
	}

	INIT_WORK(&ups->register_work, iota_ups_register_work);
	schedule_work(&ups->register_work);
	return 0;

err_stop:
	hid_hw_stop(hdev);
	return ret;
}

static void iota_ups_remove(struct hid_device *hdev)
{
	struct iota_ups *ups = hid_get_drvdata(hdev);

	cancel_work_sync(&ups->register_work);
	hid_hw_close(hdev);
	hid_hw_stop(hdev);
}

static struct hid_driver iota_ups_driver = {
	.name      = "lattepanda-iota-ups",
	.id_table  = iota_ups_devices,
	.probe     = iota_ups_probe,
	.remove    = iota_ups_remove,
	.raw_event = iota_ups_raw_event,
};
module_hid_driver(iota_ups_driver);
