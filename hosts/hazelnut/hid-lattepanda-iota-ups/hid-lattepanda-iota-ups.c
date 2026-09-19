// SPDX-License-Identifier: GPL-2.0
// Upstream LKML patch v3 by Andrew Maney <andrewmaney05@gmail.com>
// "[PATCH v3] HID: Expose LattePanda IOTA UPS as a power_supply device"
// https://lkml.iu.edu/hypermail/linux/kernel/2605.2/12097.html
//
// Local additions vs. upstream:
//   - ENERGY_FULL_DESIGN / ENERGY_FULL / ENERGY_NOW derived from capacity %
//     so that UPower has a non-zero energy baseline to work from.
//   - POWER_NOW computed from the real elapsed time between consecutive 1%
//     capacity steps (with EMA smoothing), avoiding UPower's wildly wrong
//     instantaneous rate when it happens to poll right at a step boundary.
//   - energy_full_uwh module param lets you tune to your actual cell capacity.
//     Default: 3 × 3500mAh × 3.7V = 38,850,000 µWh.
#include <linux/power_supply.h>
#include <linux/completion.h>
#include <linux/workqueue.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/spinlock.h>
#include <linux/math64.h>
#include <linux/ktime.h>
#include <linux/hid.h>
#include <linux/usb.h>

#define USB_VENDOR_ID_LATTEPANDA_IOTA     0x2341
#define USB_DEVICE_ID_LATTEPANDA_IOTA_UPS 0x8036

#define REPORT_ID_CAPACITY 0x0C
#define REPORT_ID_STATUS   0x07

#define STATUS_PLUGGED_IN  BIT(0)
#define STATUS_DISCHARGING BIT(1)
#define STATUS_CHARGING    BIT(2)

/* 3 × 3500mAh × 3.7V = 38,850,000 µWh */
#define ENERGY_FULL_DEFAULT_UWH 38850000

static unsigned int energy_full_uwh = ENERGY_FULL_DEFAULT_UWH;
module_param(energy_full_uwh, uint, 0444);
MODULE_PARM_DESC(energy_full_uwh,
	"Battery design capacity in µWh (default: 38850000 = 3×3500mAh@3.7V)");

MODULE_AUTHOR("Andrew Maney");
MODULE_DESCRIPTION("LattePanda IOTA UPS power supply driver");
MODULE_LICENSE("GPL");

struct iota_ups {
	struct power_supply_desc psu_desc;
	struct power_supply *psu;
	struct hid_device *hiddev;
	spinlock_t lock; /* Protects all cached values below */

	bool plugged_in;
	char serial[64];
	int charge_limit;
	int psu_status;
	int capacity;

	/* Rate tracking: time of last capacity change + smoothed power (µW) */
	ktime_t last_capacity_time;
	int power_now_uw;

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
		val->intval = ups->power_now_uw;
		break;
	case POWER_SUPPLY_PROP_PRESENT:
		val->intval = 1;
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

/*
 * Compute power_now (µW) from the elapsed time since the last capacity step.
 * Uses a 50% EMA to smooth across multiple steps and avoid single-sample
 * spikes. Called under ups->lock with the new capacity already validated.
 */
static void iota_ups_update_power(struct iota_ups *ups, int old_cap, int new_cap)
{
	ktime_t now = ktime_get();
	s64 delta_ms;
	u64 energy_delta_uwh;
	int new_power_uw;

	/* Skip on first reading — no previous timestamp to compare against */
	if (!ktime_to_ns(ups->last_capacity_time))
		goto out;

	delta_ms = ktime_to_ms(ktime_sub(now, ups->last_capacity_time));
	if (delta_ms <= 0)
		goto out;

	/* µWh per 1% step, scaled by number of steps jumped */
	energy_delta_uwh = div64_u64((u64)energy_full_uwh * abs(new_cap - old_cap), 100);

	/*
	 * power_uw = energy_delta_uwh [µWh] × 3,600,000 [ms/h] / delta_ms
	 * Max value before div: ~3.885×10^7 × 3.6×10^6 = ~1.4×10^14 — fits u64.
	 */
	new_power_uw = (int)div64_u64(energy_delta_uwh * 3600000ULL, (u64)delta_ms);

	/* 50% EMA: blend new measurement with running average */
	ups->power_now_uw = ups->power_now_uw
		? (ups->power_now_uw + new_power_uw) / 2
		: new_power_uw;

out:
	ups->last_capacity_time = now;
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
		u8 status = data[1];
		int new_status;
		bool plugged_in = !!(status & STATUS_PLUGGED_IN);

		if (status & STATUS_CHARGING) {
			if (ups->capacity >= ups->charge_limit)
				new_status = POWER_SUPPLY_STATUS_FULL;
			else
				new_status = POWER_SUPPLY_STATUS_CHARGING;
		} else if (status & STATUS_DISCHARGING) {
			new_status = POWER_SUPPLY_STATUS_DISCHARGING;
		} else if (plugged_in) {
			new_status = POWER_SUPPLY_STATUS_NOT_CHARGING;
		} else {
			new_status = POWER_SUPPLY_STATUS_UNKNOWN;
		}

		if (new_status != ups->psu_status || plugged_in != ups->plugged_in) {
			bool was_charging = (ups->psu_status == POWER_SUPPLY_STATUS_CHARGING);
			bool is_charging  = (new_status      == POWER_SUPPLY_STATUS_CHARGING);

			ups->plugged_in = plugged_in;
			ups->psu_status = new_status;

			/*
			 * Reset the rate only when genuinely flipping between
			 * charging and discharging — not on the initial
			 * UNKNOWN→Discharging transition at boot, which would
			 * wipe the timestamp set by the first capacity report
			 * and delay power_now by an extra 1% step.
			 */
			if (was_charging != is_charging) {
				ups->power_now_uw = 0;
				ups->last_capacity_time = ktime_set(0, 0);
			}
			changed = true;
		}

		ups->got_status = true;
		break;
	}

	case REPORT_ID_CAPACITY: {
		int new_cap = clamp((int)data[1], 0, 100);

		if (new_cap != ups->capacity) {
			iota_ups_update_power(ups, ups->capacity, new_cap);
			ups->capacity = new_cap;
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
	ups->charge_limit = 100;
	ups->last_capacity_time = ktime_set(0, 0);

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
