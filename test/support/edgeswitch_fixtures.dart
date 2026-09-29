// لقطاتٌ **حقيقيّة** من جهاز EdgeSwitch ES-24-250W (‏firmware 1.9.2).
// التُقطت من `/api/v1.0/` مباشرةً في ٢٠٢٦-٠٩-٢٨.
//
// ⚠️ لا اعتماد هنا ولا توكن — الرؤوس والأجسام الحسّاسة مستبعَدة عمداً.
// و`capabilities` من `device` محذوفة: ٱثنا عشر كيلوبايت لا يقرؤها
// المحلّل، ووجودها يُخفي ما يهمّ في المراجعة.

/// `GET /api/v1.0/device`
const String kEsDeviceJson = r'''
{
  "errorCodes": [],
  "identification": {
    "mac": "e4:38:83:db:b3:ab",
    "model": "ES-24-250W",
    "family": "EdgeSwitch",
    "firmwareVersion": "1.9.2",
    "firmware": "ES.bcmwh.v1.9.2.5322630.200807.0830",
    "product": "EdgeSwitch 24 250W",
    "serverVersion": "1.1.3",
    "bridgeVersion": "0.12.2"
  }
}
''';

/// `GET /api/v1.0/system`
const String kEsSystemJson = r'''
{
  "hostname": "UBNT EdgeSwitch",
  "timezone": "Other",
  "domainName": "",
  "factoryDefault": false,
  "stp": {
    "enabled": true,
    "version": "MSTP",
    "maxAge": 20,
    "helloTime": 2,
    "forwardDelay": 15,
    "priority": 32768
  },
  "analyticsEnabled": true,
  "dnsServers": [],
  "defaultGateway": [
    {
      "type": "static",
      "version": "v4",
      "address": "10.64.100.1"
    }
  ],
  "users": [
    {
      "username": "ubnt",
      "readOnly": false
    }
  ],
  "management": {
    "vlanID": 1,
    "addresses": [
      {
        "type": "static",
        "version": "v4",
        "cidr": "10.64.100.3/24",
        "eui64": false
      },
      {
        "type": "dynamic",
        "version": "v6",
        "cidr": "fe80::e638:83ff:fedb:b3ab/64",
        "eui64": true,
        "origin": "linkLocal"
      }
    ]
  }
}
''';

/// `GET /api/v1.0/statistics` — مصفوفةٌ من لقطةٍ واحدة لا سلسلة زمنيّة.
const String kEsStatisticsJson = r'''
[
  {
    "timestamp": 1790544147862,
    "device": {
      "cpu": [
        {
          "identifier": "ARMv7 Processor rev 1 (v7l)",
          "usage": 72
        }
      ],
      "ram": {
        "usage": 73,
        "free": 70127616,
        "total": 262553600
      },
      "temperatures": [
        {
          "name": "TEMP-1",
          "type": "other",
          "value": 39.0
        },
        {
          "name": "TEMP-2",
          "type": "other",
          "value": 29.0
        },
        {
          "name": "PoE-01",
          "type": "other",
          "value": 29.0
        },
        {
          "name": "PoE-02",
          "type": "other",
          "value": 29.0
        },
        {
          "name": "PoE-03",
          "type": "other",
          "value": 31.0
        },
        {
          "name": "PoE-04",
          "type": "other",
          "value": 31.0
        },
        {
          "name": "PoE-05",
          "type": "other",
          "value": 25.0
        },
        {
          "name": "PoE-06",
          "type": "other",
          "value": 25.0
        }
      ],
      "power": [],
      "storage": [],
      "fanSpeeds": [
        {
          "name": "FAN-1 (fixed)",
          "value": 0
        },
        {
          "name": "FAN-2 (fixed)",
          "value": 0
        },
        {
          "name": "FAN-3 (fixed)",
          "value": 0
        },
        {
          "name": "FAN-4 (fixed)",
          "value": 0
        }
      ],
      "uptime": 896456
    },
    "interfaces": [
      {
        "id": "0/1",
        "name": "",
        "statistics": {
          "dropped": 0,
          "errors": 0,
          "txErrors": 0,
          "rxErrors": 0,
          "rate": 2142048,
          "txRate": 2044800,
          "rxRate": 97248,
          "bytes": 233584246268,
          "txBytes": 212438344567,
          "rxBytes": 21145901701,
          "packets": 231221094,
          "txPackets": 173353658,
          "rxPackets": 57867436,
          "pps": 319,
          "txPPS": 226,
          "rxPPS": 93,
          "poePower": 0.0
        }
      },
      {
        "id": "0/2",
        "name": "",
        "statistics": {
          "dropped": 0,
          "errors": 0,
          "txErrors": 0,
          "rxErrors": 0,
          "rate": 0,
          "txRate": 0,
          "rxRate": 0,
          "bytes": 0,
          "txBytes": 0,
          "rxBytes": 0,
          "packets": 0,
          "txPackets": 0,
          "rxPackets": 0,
          "pps": 0,
          "txPPS": 0,
          "rxPPS": 0,
          "poePower": 0.0
        }
      },
      {
        "id": "3/1",
        "name": "",
        "statistics": {
          "dropped": 0,
          "errors": 0,
          "txErrors": 0,
          "rxErrors": 0,
          "rate": 0,
          "txRate": 0,
          "rxRate": 0,
          "bytes": 0,
          "txBytes": 0,
          "rxBytes": 0,
          "packets": 0,
          "txPackets": 0,
          "rxPackets": 0,
          "pps": 0,
          "txPPS": 0,
          "rxPPS": 0,
          "poePower": 0.0
        }
      }
    ]
  }
]
''';

/// `GET /api/v1.0/interfaces` — عيّنةٌ تمثّل الحالات: منفذٌ يعمل،
/// ومنفذٌ بلا كابل، ومنفذ PoE، ومدخلٌ ليس منفذاً (يجب أن يُستبعَد).
const String kEsInterfacesJson = r'''
[
  {
    "identification": {
      "id": "0/1",
      "name": "",
      "mac": "e4:38:83:db:b3:ab",
      "type": "port"
    },
    "status": {
      "timestamp": 1790544145005,
      "enabled": true,
      "comment": "",
      "description": "1 Gbps - Full Duplex",
      "plugged": true,
      "currentSpeed": "1000-full",
      "speed": "auto",
      "arpProxy": true,
      "mtu": 1518,
      "cableLength": 0
    },
    "addresses": [
      {
        "type": "static",
        "version": "v4",
        "cidr": "10.64.100.3/24",
        "eui64": false
      },
      {
        "type": "dynamic",
        "version": "v6",
        "cidr": "fe80::e638:83ff:fedb:b3ab/64",
        "eui64": true,
        "origin": "linkLocal"
      }
    ],
    "port": {
      "stp": {
        "enabled": true,
        "edgePort": "auto",
        "pathCost": 0,
        "portPriority": 128
      },
      "dhcpSnooping": false,
      "poe": "off",
      "flowControl": false,
      "routed": false,
      "isolated": true,
      "pingWatchdog": {
        "enabled": false,
        "address": "0.0.0.0",
        "failureCount": 3,
        "interval": 15,
        "offDelay": 5,
        "startDelay": 300
      }
    }
  },
  {
    "identification": {
      "id": "0/2",
      "name": "",
      "mac": "e4:38:83:db:b3:ab",
      "type": "port"
    },
    "status": {
      "timestamp": 1790544145016,
      "enabled": true,
      "comment": "",
      "description": "",
      "plugged": false,
      "currentSpeed": "",
      "speed": "auto",
      "arpProxy": true,
      "mtu": 1518,
      "cableLength": 0
    },
    "addresses": [
      {
        "type": "static",
        "version": "v4",
        "cidr": "10.64.100.3/24",
        "eui64": false
      },
      {
        "type": "dynamic",
        "version": "v6",
        "cidr": "fe80::e638:83ff:fedb:b3ab/64",
        "eui64": true,
        "origin": "linkLocal"
      }
    ],
    "port": {
      "stp": {
        "enabled": true,
        "edgePort": "auto",
        "pathCost": 0,
        "portPriority": 128
      },
      "dhcpSnooping": false,
      "poe": "off",
      "flowControl": false,
      "routed": false,
      "isolated": true,
      "pingWatchdog": {
        "enabled": false,
        "address": "0.0.0.0",
        "failureCount": 3,
        "interval": 15,
        "offDelay": 5,
        "startDelay": 300
      }
    }
  },
  {
    "identification": {
      "id": "3/1",
      "name": "",
      "mac": "e4:38:83:db:b3:ab",
      "type": "lag"
    },
    "status": {
      "timestamp": 1790544146015,
      "enabled": true,
      "comment": "",
      "description": "",
      "plugged": false,
      "currentSpeed": "",
      "speed": "",
      "arpProxy": false,
      "mtu": 1518,
      "cableLength": 0
    },
    "addresses": [],
    "lag": {
      "stp": {
        "enabled": true,
        "edgePort": "auto",
        "pathCost": 0,
        "portPriority": 96
      },
      "dhcpSnooping": false,
      "static": false,
      "linkTrap": true,
      "loadBalance": "src_dst_mac_l2",
      "interfaces": []
    }
  }
]
''';

/// صفحة الجذر قبل أيّ دخول — أساس التمييز عن airOS.
const String kEsRootHtml = r'''
<!doctype html><html lang="en"><head><title>Ubiquiti EdgeSwitch</title>
</head><body><div id="app"></div></body></html>
''';
