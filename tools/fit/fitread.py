"""Minimal FIT decoder: enough of the binary protocol to read activity files,
including developer fields and their self-describing names."""
import struct, datetime

FIT_EPOCH = 631065600  # 1989-12-31 UTC in unix seconds

# base type -> (struct code, size, invalid value)
BASE = {
    0x00: ('B', 1, 0xFF), 0x01: ('b', 1, 0x7F), 0x02: ('B', 1, 0xFF),
    0x83: ('h', 2, 0x7FFF), 0x84: ('H', 2, 0xFFFF),
    0x85: ('i', 4, 0x7FFFFFFF), 0x86: ('I', 4, 0xFFFFFFFF),
    0x07: ('s', 1, 0x00), 0x88: ('f', 4, None), 0x89: ('d', 8, None),
    0x0A: ('B', 1, 0x00), 0x8B: ('H', 2, 0x0000), 0x8C: ('I', 4, 0x00000000),
    0x0D: ('B', 1, 0xFF), 0x8E: ('q', 8, 0x7FFFFFFFFFFFFFFF),
    0x8F: ('Q', 8, 0xFFFFFFFFFFFFFFFF), 0x90: ('Q', 8, 0),
}

RECORD, SESSION, LAP, FILE_ID, EVENT, FIELD_DESC = 20, 18, 19, 0, 21, 206

# Which Connect IQ app wrote the developer fields, and which version of it.
# Worth reading before trusting anything in a file: an archive of games off
# one watch can hold recordings from several different apps, and mistaking
# another app's automatic shift detector for a player's own lap presses is
# a mistake that survives a long way into an analysis.
DEV_DATA_ID = 207
DEVICE_INFO = 23

# Written by the watch firmware, not by this app: one per lap and one for the
# session. Every shift is a lap here, so this is a heart rate zone breakdown
# per shift - which Garmin Connect records and never shows.
TIME_IN_ZONE = 216

# field number -> name, for the messages we care about
NAMES = {
    RECORD: {253:'timestamp', 0:'lat', 1:'lon', 2:'altitude', 3:'heart_rate',
             4:'cadence', 5:'distance', 6:'speed', 73:'enh_speed'},
    SESSION: {253:'timestamp', 2:'start_time', 5:'sport', 6:'sub_sport',
              7:'total_elapsed_time', 8:'total_timer_time', 9:'total_distance',
              11:'total_calories', 16:'avg_heart_rate', 17:'max_heart_rate',
              26:'num_laps', 18:'avg_cadence', 14:'avg_speed', 15:'max_speed'},
    LAP: {253:'timestamp', 2:'start_time', 7:'total_elapsed_time',
          8:'total_timer_time', 9:'total_distance', 11:'total_calories',
          15:'avg_heart_rate', 16:'max_heart_rate', 25:'sport', 23:'intensity',
          24:'lap_trigger'},
    FILE_ID: {0:'type', 1:'manufacturer', 2:'product', 4:'time_created'},
    # NOTE field 3 is serial_number and is DROPPED outright, in DROP below.
    # Leaving it merely unnamed is not redaction: it still decodes, as 'f3',
    # and still prints - which is how the watch's own serial, purged from this
    # repo once already, turned up in a debug dump the first time this message
    # was parsed. Nothing here needs it; sensors are named by type and make.
    DEVICE_INFO: {253:'timestamp', 0:'device_index', 1:'device_type',
                  2:'manufacturer', 4:'product', 5:'software_version',
                  10:'battery_voltage', 11:'battery_status',
                  25:'source_type', 27:'product_name'},
    EVENT: {253:'timestamp', 0:'event', 1:'event_type', 4:'event_group'},
    FIELD_DESC: {0:'developer_data_index', 1:'field_definition_number',
                 2:'fit_base_type_id', 3:'field_name', 8:'units',
                 14:'native_mesg_num'},
    DEV_DATA_ID: {0:'developer_id', 1:'application_id', 2:'manufacturer_id',
                  3:'developer_data_index', 4:'application_version'},
    TIME_IN_ZONE: {253:'timestamp', 0:'reference_mesg', 1:'reference_index',
                   2:'time_in_hr_zone', 5:'time_in_power_zone',
                   6:'hr_zone_high_boundary', 9:'time_in_speed_zone',
                   10:'hr_calc_type', 11:'max_heart_rate',
                   12:'resting_heart_rate', 13:'threshold_heart_rate',
                   14:'pwr_calc_type', 15:'functional_threshold_power'},
}

# Fields whose value is an array whose POSITION is its meaning - zone 3 is
# wherever index 3 is. The ordinary decode drops invalid entries, which for
# these silently renumbers the zones: a file with no time in zone 1 would
# report zone 2's seconds as zone 1's. They have to keep their holes.
POSITIONAL = {(TIME_IN_ZONE, 2), (TIME_IN_ZONE, 5), (TIME_IN_ZONE, 6),
              (TIME_IN_ZONE, 9)}

# Fields that are read off the wire and then thrown away, so that no caller can
# print them by accident. device_info.serial_number identifies a specific piece
# of hardware - the watch, or a paired strap - and nothing this repo does needs
# it. It has to be dropped at the decoder, not at the printer.
#
# Field 29 is the same problem wearing different clothes: on a Bluetooth
# sensor it carries the six bytes of the device's MAC address, which is a
# permanent hardware identifier for a thing strapped to the user's chest. It
# decoded as a harmless-looking 'f29' list of six numbers and printed on the
# very first dump of a real strap.
DROP = {(DEVICE_INFO, 3), (DEVICE_INFO, 29)}

# Fields that are raw bytes rather than numbers, and must not be filtered at
# all. A UUID is sixteen arbitrary bytes and 0xFF is one of the legal ones -
# the ordinary decode treats 0xFF as "invalid" and drops it, which silently
# shortens the UUID and makes it match nothing. Ice Hockey Tracker's really
# does contain an 0xFF, which is how this was found.
RAW = {(DEV_DATA_ID, 0), (DEV_DATA_ID, 1)}

SPORT = {0:'generic',1:'running',2:'cycling',4:'fitness_equipment',5:'swimming',
         6:'basketball',7:'soccer',10:'training',11:'walking',15:'rowing',
         17:'hiking',18:'multisport',25:'golf',30:'inline_skating',
         33:'ice_skating',48:'floor_climbing',53:'hockey_?',73:'hockey'}
SUBSPORT = {0:'generic',90:'field',91:'ice',58:'virtual_activity'}


def _decode(raw, base, endian):
    code, size, invalid = BASE.get(base, ('B', 1, 0xFF))
    if code == 's':
        txt = raw.split(b'\x00')[0]
        try:
            return txt.decode('utf-8', 'replace') or None
        except Exception:
            return None
    n = len(raw) // size
    if n == 0:
        return None
    vals = struct.unpack(endian + code * n, raw[:n * size])
    vals = [None if (invalid is not None and v == invalid) else v for v in vals]
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return vals[0] if len(vals) == 1 else vals


def _decode_positional(raw, base, endian):
    """Decode an array field keeping every slot, invalid ones included as None."""
    code, size, invalid = BASE.get(base, ('B', 1, 0xFF))
    if code == 's':
        return _decode(raw, base, endian)
    n = len(raw) // size
    if n == 0:
        return []
    vals = struct.unpack(endian + code * n, raw[:n * size])
    return [None if (invalid is not None and v == invalid) else v for v in vals]


def parse(path):
    data = open(path, 'rb').read()
    hdr = data[0]
    pos = hdr
    size = struct.unpack('<I', data[4:8])[0]
    end = min(hdr + size, len(data))

    defs = {}          # local msg type -> definition
    devdefs = {}       # (dev_index, field_num) -> {'name','base','units'}
    out = {'record': [], 'session': [], 'lap': [], 'file_id': [],
           'event': [], 'time_in_zone': [], 'devfields': devdefs,
           'developer_data_id': [], 'device_info': []}

    while pos < end:
        h = data[pos]; pos += 1
        if h & 0x80:                      # compressed timestamp header
            local = (h >> 5) & 0x03
            isdef = False
        else:
            local = h & 0x0F
            isdef = bool(h & 0x40)

        if isdef:
            pos += 1                      # reserved
            endian = '<' if data[pos] == 0 else '>'; pos += 1
            gnum = struct.unpack(endian + 'H', data[pos:pos + 2])[0]; pos += 2
            nfields = data[pos]; pos += 1
            fields = []
            for _ in range(nfields):
                fnum, fsize, ftype = data[pos], data[pos + 1], data[pos + 2]
                pos += 3
                fields.append((fnum, fsize, ftype))
            devs = []
            if h & 0x20:
                ndev = data[pos]; pos += 1
                for _ in range(ndev):
                    fnum, fsize, didx = data[pos], data[pos + 1], data[pos + 2]
                    pos += 3
                    devs.append((fnum, fsize, didx))
            defs[local] = (gnum, endian, fields, devs)
            continue

        d = defs.get(local)
        if d is None:
            break                         # unreadable from here
        gnum, endian, fields, devs = d
        msg = {}
        for fnum, fsize, ftype in fields:
            raw = data[pos:pos + fsize]; pos += fsize
            if (gnum, fnum) in DROP:
                continue
            name = NAMES.get(gnum, {}).get(fnum, 'f%d' % fnum)
            if (gnum, fnum) in RAW:
                msg[name] = bytes(raw)
            elif (gnum, fnum) in POSITIONAL:
                msg[name] = _decode_positional(raw, ftype, endian)
            else:
                msg[name] = _decode(raw, ftype, endian)
        for fnum, fsize, didx in devs:
            raw = data[pos:pos + fsize]; pos += fsize
            meta = devdefs.get((didx, fnum))
            if meta:
                msg['dev:' + meta['name']] = _decode(raw, meta['base'], endian)

        if gnum == FIELD_DESC:
            key = (msg.get('developer_data_index'),
                   msg.get('field_definition_number'))
            devdefs[key] = {'name': msg.get('field_name') or 'dev%s' % (key,),
                            'base': msg.get('fit_base_type_id') or 0x02,
                            'units': msg.get('units')}
        elif gnum == RECORD:
            out['record'].append(msg)
        elif gnum == SESSION:
            out['session'].append(msg)
        elif gnum == LAP:
            out['lap'].append(msg)
        elif gnum == FILE_ID:
            out['file_id'].append(msg)
        elif gnum == EVENT:
            out['event'].append(msg)
        elif gnum == TIME_IN_ZONE:
            out['time_in_zone'].append(msg)
        elif gnum == DEV_DATA_ID:
            out['developer_data_id'].append(msg)
        elif gnum == DEVICE_INFO:
            out['device_info'].append(msg)
    return out


def app_uuid(msg):
    """The Connect IQ app UUID out of a developer_data_id message, or None.

    FIT carries it as sixteen raw bytes; the store addresses the same app as a
    dashed UUID, so render it that way - the point of having it is to paste it
    into apps.garmin.com and find out whose app wrote the file.
    """
    raw = msg.get('application_id')
    if not isinstance(raw, (bytes, bytearray)):
        return None
    b = bytes(raw)
    if len(b) != 16:
        return b.hex()
    h = b.hex()
    return '%s-%s-%s-%s-%s' % (h[0:8], h[8:12], h[12:16], h[16:20], h[20:32])


def when(ts):
    if ts is None:
        return None
    return datetime.datetime.utcfromtimestamp(ts + FIT_EPOCH)


# source_type, from the FIT profile. 5 is the watch itself; everything else
# arrived over a radio, which is what makes it a separate sensor.
SOURCE_TYPE = {0: 'ANT', 1: 'ANT+', 2: 'Bluetooth',
               3: 'Bluetooth Low Energy', 4: 'Wi-Fi', 5: 'local (the watch)'}

# Enough of the manufacturer table to name what turns up on a wrist. Anything
# else prints as its number rather than guessing.
MANUFACTURER = {1: 'Garmin', 13: 'Suunto', 23: 'Suunto', 32: 'Wahoo',
                63: 'Polar', 68: 'Magene', 95: 'Stages', 263: 'Coospo',
                265: 'Coospo', 294: 'Coospo'}

# What counts as a heart-rate sensor depends on how it is attached, because
# device_type is interpreted against a different table per source_type. Over
# ANT+ the heart-rate profile is 120; over Bluetooth it is 1. Testing only for
# 120 therefore says "not a heart rate sensor" about every BLE strap.
ANTPLUS_HR = 120
BLE_HR = 1
BLE_SOURCES = (2, 3)        # Bluetooth, Bluetooth Low Energy
ANT_SOURCES = (0, 1)        # ANT, ANT+


def _is_hr(src, dtype):
    if src in ANT_SOURCES:
        return dtype == ANTPLUS_HR
    if src in BLE_SOURCES:
        return dtype == BLE_HR
    return False


def external_sensors(f):
    """Every sensor the file says arrived over a radio.

    Anything with source_type 5 is the watch describing its own insides - a
    Forerunner 570 lists five of them - so "external" means source_type is
    something else. That, not the ANT+ heart-rate profile, is the test: a
    strap paired over Bluetooth never sets device_type 120, so keying on 120
    silently reports "no strap" for exactly the setup it was written to check.

    Returns dicts with 'name', 'how', 'is_hr' and 'battery'. An empty list
    means the activity ran on wrist optical alone, which is the difference
    between "the strap was used" and "the strap was paired and ignored".
    """
    seen, out = [], []
    for m in f.get('device_info', []):
        src = m.get('source_type')
        if src in (5, None):
            continue                      # the watch's own subsystems
        manu = m.get('manufacturer')
        # A BLE strap need not tell the watch who made it: the Coospo H6
        # reports no manufacturer and no product name at all, so the honest
        # label is what it is rather than "manufacturer None".
        if m.get('product_name'):
            label = m['product_name']
        elif manu in MANUFACTURER:
            label = MANUFACTURER[manu]
        elif manu is not None:
            label = 'manufacturer %s' % manu
        else:
            label = 'unnamed sensor'
        how = SOURCE_TYPE.get(src, 'source_type %s' % src)
        key = (label, how)
        if key in seen:
            continue
        seen.append(key)
        out.append({'name': label, 'how': how,
                    'is_hr': _is_hr(src, m.get('device_type')),
                    'battery': m.get('battery_status')})
    return out
