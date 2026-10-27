// ردودٌ حقيقيّة مسجّلة من جهازي popq التجريبيّين (٢٧ أكتوبر ٢٠٢٦) — الماكات والإحداثيّات مُستبدلة.
// airFiber 4X (AF06 v4.1.0): ناتج `mca-status`. Wave Long-Range (4.1.1): ردود `/api/v1.0/{statistics,device,system,interfaces}`.

const af4xMcaStatus = r'''
deviceName=UBNT,deviceId=00:11:22:33:44:55,firmwareVersion=AF06.am1808.v4.1.0.250.200318.1133,platform=airFiber 4X,deviceIp=10.150.150.2
essid=bo-sajad313
remoteMac=00:11:22:33:44:55
remoteIp=10.150.150.3
distance=4142
latitude=33.3
longitude=44.4
altitude=43
gpsFixed=2
cfgCrc=77e9fbc9
wlanUptime=1147
afOpmode=master
afLinkState=operational
afDuplex=half
afTxmodrate=8x
afTxpower=24
afTxpowerEirp=50
afTxfreq=4850
afRxfreq=4770
afTxchanbw=56
afRxchanbw=56
afRxcapacity=115700480
afTxcapacity=344552320
afRxpower0=-45
afRxpower1=-45
signal=-41
lanRxBytes=10096866039227
lanRxPackets=8528245309
lanRxErrors=0
lanTxBytes=780197904550
lanTxPackets=3413227092
lanTxErrors=151
lanSpeed=1000Mbps-Full
lanPlugged=1
uptime=776835
loadavg=0
memTotal=62064
memFree=41108
memBuffers=3888
''';

const waveStatisticsJson = r'''
[
 {
  "interfaces": [
   {
    "statistics": {
     "txPackets": 13772221007,
     "errors": 0,
     "rxPackets": 2926213385,
     "rxBytes": 750510803831,
     "txDropped": 0,
     "txBytes": 16860012750972,
     "txPPS": 5779,
     "dropped": 0,
     "rxPPS": 4687,
     "txRate": 45041108,
     "txErrors": 0,
     "rxRate": 29544064,
     "rxErrors": 0,
     "rxDropped": 0
    },
    "status": {
     "enabled": true,
     "mtu": 1500,
     "type": "wireless"
    },
    "name": "60 GHz",
    "id": "wlan0"
   },
   {
    "statistics": {
     "txPackets": 85355,
     "errors": 52665,
     "rxPackets": 16345,
     "rxBytes": 3794261,
     "txDropped": 0,
     "txBytes": 19295801,
     "txPPS": 0,
     "dropped": 0,
     "rxPPS": 0,
     "txRate": 0,
     "txErrors": 52665,
     "rxRate": 0,
     "rxErrors": 0,
     "rxDropped": 0
    },
    "status": {
     "enabled": true,
     "mtu": 1500,
     "type": "wireless"
    },
    "name": "5 GHz Backup",
    "id": "ath0"
   },
   {
    "statistics": {
     "txPackets": 5338095339,
     "errors": 0,
     "rxPackets": 13772235479,
     "rxBytes": 16708616970004,
     "txDropped": 0,
     "txBytes": 1417127361965,
     "txPPS": 4746,
     "dropped": 0,
     "rxPPS": 5792,
     "txRate": 29915406,
     "txErrors": 0,
     "rxRate": 44487960,
     "rxErrors": 0,
     "rxDropped": 0
    },
    "status": {
     "currentSpeed": "1000-full",
     "plugged": true,
     "enabled": true,
     "mtu": 1500,
     "media": "GE",
     "type": "ethernet"
    },
    "name": "Ethernet Port",
    "id": "eth0"
   },
   {
    "statistics": {
     "txPackets": 1666487,
     "errors": 0,
     "rxPackets": 2508008,
     "rxBytes": 1617683986,
     "txDropped": 0,
     "txBytes": 1578946556,
     "txPPS": 16,
     "dropped": 12681,
     "rxPPS": 19,
     "txRate": 45631,
     "txErrors": 0,
     "rxRate": 36578,
     "rxErrors": 0,
     "rxDropped": 12681
    },
    "status": {
     "enabled": true,
     "mtu": 1500,
     "type": "bridge"
    },
    "name": "Data",
    "id": "br0"
   }
  ],
  "timestamp": 1793059467256,
  "wireless": {
   "serviceDowntime": 0,
   "peers": [
    {
     "local": [
      {
       "active": true,
       "linkState": "active",
       "connected": true,
       "connectionTime": 407899,
       "linkQuality": {
        "airtime": {
         "dl": 5.88,
         "ul": 5.58
        },
        "capacity": {
         "ulIdeal": 1000000,
         "ul": 1000000,
         "dl": 1000000,
         "combinedIdeal": 2000000,
         "combined": 1953875,
         "dlIdeal": 1000000
        },
        "linkScore": {
         "ul": 55,
         "dl": 55,
         "ul24": 60,
         "dl24": 63,
         "ul2": 58,
         "dl2": 55
        },
        "signal": -55,
        "signalDay": -54,
        "mcs": {
         "rxIdxIdeal": 12,
         "txIdxIdeal": 12,
         "rxLabel": "16QAM",
         "txRate": 4,
         "rxIdx": 10,
         "txIdx": 9,
         "rxRate": 8,
         "txLabel": "QPSK"
        },
        "idealSignal": -38
       },
       "remoteId": "main",
       "id": "main"
      },
      {
       "active": false,
       "linkState": "connected",
       "connected": true,
       "connectionTime": 268,
       "linkQuality": {
        "noiseFloor": -93,
        "idealSignal": -63,
        "signalDay": -71,
        "mcs": {
         "rxIdxIdeal": 5,
         "txIdxIdeal": 5,
         "rxLabel": "16QAM",
         "txRate": 2,
         "rxIdx": 3,
         "txIdx": 2,
         "rxRate": 4,
         "txLabel": "QPSK"
        },
        "capacity": {
         "ulIdeal": 192710,
         "ul": 96320,
         "dl": 72240,
         "combinedIdeal": 192710,
         "combined": 84280,
         "dlIdeal": 192710
        },
        "linkScore": {
         "ul": 50,
         "dl": 37,
         "ul24": 48,
         "dl24": 36,
         "ul2": 50,
         "dl2": 37
        },
        "idealSignalPerChain": [
         -63,
         -63
        ],
        "signalPerChain": [
         -73,
         -73
        ],
        "signal": -70
       },
       "remoteId": "backup",
       "id": "backup"
      }
     ],
     "common": {
      "mgmtIp": "10.160.160.3",
      "identification": {
       "model": "Wave-LR",
       "firmware": "GMC.ipq5018.v4.1.1.afbcc2cb.260525.1241",
       "family": "wave",
       "firmwareVersion": "4.1.1",
       "mac": "00:11:22:33:44:55",
       "subsystemID": "a664",
       "product": "Wave Long-Range"
      },
      "serviceTime": 407927,
      "timestamp": 1793059466237,
      "counters": {
       "txPPS": 5782,
       "rxRate": 32382299,
       "rxPPS": 6061,
       "txRate": 44677080,
       "rxPackets": 2926224363,
       "rxBytes": 9312181810388,
       "txPackets": 7618299107,
       "txBytes": 790761774259
      },
      "linkQuality": {
       "linkScore": {
        "ul2": 58,
        "ul": 55,
        "dl": 55,
        "dl2": 55
       }
      },
      "serviceUptime": 407927,
      "countryCode": "XL",
      "uptime": 407958,
      "gps": {
       "fix": true,
       "lastSync": 0,
       "alt": 49.3,
       "timeSyncEnabled": false,
       "dim": 3,
       "sats": 8,
       "dop": 0.91,
       "lon": 44.4,
       "lat": 33.3
      },
      "hostname": "Wave Long-Range",
      "interfaces": [
       {
        "statistics": {
         "txPackets": 2926224348,
         "errors": 0,
         "rxPackets": 7618279510,
         "rxBytes": 9198138058489,
         "txDropped": 0,
         "txBytes": 790761764266,
         "txPPS": 6060,
         "dropped": 0,
         "rxPPS": 12264,
         "txRate": 32355642,
         "txErrors": 0,
         "rxRate": 113395944,
         "rxErrors": 0,
         "rxDropped": 0
        },
        "status": {
         "enabled": true,
         "mtu": 1500,
         "type": "wireless"
        },
        "name": "60 GHz",
        "id": "wlan0"
       },
       {
        "statistics": {
         "txPackets": 0,
         "errors": 583,
         "rxPackets": 21525,
         "rxBytes": 4292252,
         "txDropped": 0,
         "txBytes": 0,
         "txPPS": 0,
         "dropped": 6,
         "rxPPS": 0,
         "txRate": 0,
         "txErrors": 583,
         "rxRate": 0,
         "rxErrors": 0,
         "rxDropped": 6
        },
        "status": {
         "enabled": true,
         "mtu": 1500,
         "type": "wireless"
        },
        "name": "5 GHz Backup",
        "id": "ath0"
       },
       {
        "statistics": {
         "txPackets": 7618287726,
         "errors": 4,
         "rxPackets": 2926184105,
         "rxBytes": 762205050303,
         "txDropped": 0,
         "txBytes": 9228625142383,
         "txPPS": 12246,
         "dropped": 4,
         "rxPPS": 6053,
         "txRate": 113576640,
         "txErrors": 0,
         "rxRate": 31807626,
         "rxErrors": 4,
         "rxDropped": 4
        },
        "status": {
         "currentSpeed": "1000-full",
         "plugged": true,
         "enabled": true,
         "mtu": 1500,
         "media": "GE",
         "type": "ethernet"
        },
        "name": "Ethernet Port",
        "id": "eth0"
       },
       {
        "statistics": {
         "txPackets": 852134,
         "errors": 0,
         "rxPackets": 1287655,
         "rxBytes": 852023902,
         "txDropped": 0,
         "txBytes": 780575053,
         "txPPS": 1,
         "dropped": 4990,
         "rxPPS": 3,
         "txRate": 15544,
         "txErrors": 0,
         "rxRate": 18658,
         "rxErrors": 0,
         "rxDropped": 4990
        },
        "status": {
         "enabled": true,
         "mtu": 1500,
         "type": "bridge"
        },
        "name": "Data",
        "id": "br0"
       }
      ],
      "powerTime": 407959,
      "distance": 4111,
      "cpu": [
       {
        "usage": 10,
        "identifier": "core 1"
       },
       {
        "usage": 7,
        "identifier": "core 2"
       }
      ],
      "netMode": "bridge",
      "carrierDrop": {
       "dropped": false
      },
      "ram": {
       "free": 215814144,
       "total": 420794368,
       "usage": 48
      }
     },
     "remote": [
      {
       "linkState": "active",
       "connected": true,
       "serviceActiveTime": 407926,
       "serviceTime": 407927,
       "gps": {
        "fix": true,
        "lastSync": 0,
        "alt": 49.3,
        "timeSyncEnabled": false,
        "dim": 3,
        "sats": 8,
        "dop": 0.91,
        "lon": 44.4,
        "lat": 33.3
       },
       "active": true,
       "serviceDowntime": 0,
       "id": "main",
       "antenna": {
        "gain": 46,
        "name": "WAVE-LR-60G",
        "type": "built_in"
       },
       "serviceUptime": 407927,
       "linkQuality": {
        "outputPower": {
         "conducted": 20,
         "eirp": 66
        },
        "signal": -55,
        "signalDay": -53,
        "mcs": {},
        "idealSignal": -38
       },
       "remoteId": "main",
       "name": "60 GHz"
      },
      {
       "linkState": "connected",
       "connected": true,
       "serviceActiveTime": 0,
       "serviceDowntime": 0,
       "serviceTime": 407919,
       "id": "backup",
       "active": false,
       "dfs": {
        "enabled": false,
        "cacDuration": 0,
        "cacRemaining": 0
       },
       "gps": {
        "fix": true,
        "lastSync": 0,
        "alt": 49.3,
        "timeSyncEnabled": false,
        "dim": 3,
        "sats": 8,
        "dop": 0.91,
        "lon": 44.4,
        "lat": 33.3
       },
       "antenna": {
        "gain": 22,
        "name": "WAVE-LR-5G",
        "type": "built_in"
       },
       "serviceUptime": 279254,
       "linkQuality": {
        "noiseFloor": -93,
        "signal": -69,
        "signalPerChain": [
         -72,
         -72
        ],
        "mcs": {},
        "outputPower": {
         "conducted": 12,
         "eirp": 34
        },
        "idealSignalPerChain": [
         -63,
         -63
        ],
        "idealSignal": -63,
        "signalDay": -69
       },
       "name": "5 GHz Backup",
       "remoteId": "backup"
      }
     ]
    }
   ],
   "radios": [
    {
     "linkState": "connected",
     "serviceUptime": 776835,
     "waveAi": false,
     "gpsSyncState": 2,
     "serviceTime": 776887,
     "id": "main",
     "serviceActiveTime": 776831,
     "serviceDowntime": 0,
     "antenna": {
      "gain": 46,
      "name": "WAVE-LR-60G",
      "type": "built_in"
     },
     "outputPower": {
      "conducted": 20,
      "eirp": 66
     },
     "channelWidth": {
      "tx": 2160
     },
     "linkQuality": {
      "capacity": {
       "ulIdeal": 1000000,
       "ul": 1000000,
       "dl": 1000000,
       "combinedIdeal": 2000000,
       "combined": 1953875,
       "dlIdeal": 1000000
      }
     },
     "channelUtilization": {
      "common": {
       "interference": 2.39
      }
     },
     "frequency": {
      "center": 68040
     }
    },
    {
     "linkState": "connected",
     "serviceDowntime": 0,
     "serviceUptime": 509280,
     "serviceTime": 776895,
     "id": "backup",
     "serviceActiveTime": 7,
     "dfs": {
      "enabled": false,
      "cacDuration": 0,
      "cacRemaining": 0
     },
     "outputPower": {
      "conducted": 12,
      "eirp": 34
     },
     "antenna": {
      "gain": 22,
      "name": "WAVE-LR-5G",
      "type": "built_in"
     },
     "channelWidth": {
      "tx": 40
     },
     "linkQuality": {
      "capacity": {
       "ulIdeal": 192710,
       "ul": 96320,
       "dl": 72240,
       "combinedIdeal": 192710,
       "combined": 84280,
       "dlIdeal": 192710
      }
     },
     "channelUtilization": {
      "ul": 0,
      "dl": 0,
      "common": {
       "interference": 4
      }
     },
     "frequency": {
      "control": 5165,
      "center": 5175
     }
    }
   ],
   "serviceUptime": 776857,
   "linkQuality": {
    "capacity": {
     "ulIdeal": 1000000,
     "ul": 1000000,
     "dl": 1000000,
     "combinedIdeal": 2000000,
     "combined": 1953875,
     "dlIdeal": 1000000
    },
    "counters": {
     "txRate": 44677080,
     "rxRate": 32382299
    },
    "linkScore": {
     "ul2": 58,
     "ul": 55,
     "dl": 55,
     "dl2": 55
    }
   },
   "serviceTime": 776895,
   "carrierDrop": {
    "dropped": false
   }
  },
  "device": {
   "temperatures": [
    {
     "value": 57,
     "name": "cpu",
     "type": "cpu"
    },
    {
     "value": 44,
     "name": "main",
     "type": "radio"
    },
    {
     "value": 52,
     "name": "backup",
     "type": "radio"
    }
   ],
   "uptime": 776936,
   "powerTime": 776936,
   "gps": {
    "fix": true,
    "lastSync": 0,
    "alt": 43.3,
    "timeSyncEnabled": false,
    "dim": 3,
    "sats": 7,
    "dop": 1.09,
    "lon": 44.4,
    "lat": 33.3
   },
   "cpu": [
    {
     "usage": 32,
     "identifier": "core 1"
    },
    {
     "usage": 6,
     "identifier": "core 2"
    }
   ],
   "ram": {
    "free": 168026112,
    "total": 420794368,
    "usage": 60
   }
  }
 }
]
''';

const waveDeviceJson = r'''
{
 "identification": {
  "firmware": "GMC.ipq5018.v4.1.1.afbcc2cb.260525.1241",
  "firmwareVersion": "4.1.1",
  "model": "Wave-LR",
  "product": "Wave Long-Range",
  "subsystemID": "a664",
  "family": "wave"
 }
}
''';

const waveSystemJson = r'''
{
 "hostname": "Wave Long-Range",
 "timezone": "Asia/Baghdad"
}
''';

const waveInterfacesJson = r'''
[
 {
  "identification": {
   "type": "bridge",
   "mac": "00:11:22:33:44:55",
   "name": "Data",
   "id": "br0"
  },
  "status": {
   "enabled": true,
   "mtu": 1500
  }
 },
 {
  "identification": {
   "type": "wireless",
   "mac": "00:11:22:33:44:55",
   "name": "60 GHz",
   "id": "wlan0"
  },
  "status": {
   "enabled": true,
   "mtu": 1500
  }
 },
 {
  "identification": {
   "type": "wireless",
   "mac": "00:11:22:33:44:55",
   "name": "5 GHz Backup",
   "id": "ath0"
  },
  "status": {
   "enabled": true,
   "mtu": 1500
  }
 },
 {
  "identification": {
   "type": "ethernet",
   "mac": "00:11:22:33:44:55",
   "name": "Ethernet Port",
   "id": "eth0"
  },
  "status": {
   "speed": "1000-full",
   "enabled": true,
   "mtu": 1500,
   "currentSpeed": "1000-full",
   "plugged": true
  }
 }
]
''';
