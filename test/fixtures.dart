// Test verileri: gerçek servislerin yanıt BİÇİMİNİ taklit eder (değerler örnektir).

const isparkListJson = [
  {
    'parkID': 1001,
    'parkName': 'TAKSİM KATLI OTOPARKI',
    'lat': '41.0372',
    'lng': '28.9861',
    'capacity': 400,
    'emptyCapacity': 120,
    'workHours': '24 Saat',
    'parkType': 'KAPALI OTOPARK',
    'freeTime': 15,
    'district': 'BEYOĞLU',
    'isOpen': 1,
  },
  {
    'parkID': 1002,
    'parkName': 'CUMHURİYET CADDESİ YOL ÜSTÜ',
    'lat': 41.0405,
    'lng': 28.9870,
    'capacity': 30,
    'emptyCapacity': 0,
    'workHours': '08:00-20:00',
    'parkType': 'YOL ÜSTÜ',
    'freeTime': 0,
    'district': 'ŞİŞLİ',
    'isOpen': 1,
  },
  {
    'parkID': 1003,
    'parkName': 'KAPALI TEST',
    'lat': '41.05',
    'lng': '28.99',
    'capacity': 0,
    'emptyCapacity': 0,
    'parkType': 'AÇIK OTOPARK',
    'district': 'ŞİŞLİ',
    'isOpen': 0,
  },
  // Geçersiz kayıtlar ayıklanmalı:
  {'parkID': 1004, 'parkName': 'KOORDİNATSIZ'},
  {'parkID': 1005, 'parkName': 'YURT DIŞI', 'lat': '48.85', 'lng': '2.35', 'capacity': 10, 'emptyCapacity': 5},
];

/// 2020 dönemi Türkçe alan adlarıyla yanıt (geriye dönük uyumluluk).
const isparkLegacyJson = [
  {
    'ParkID': 77,
    'ParkAdi': 'ESKİ BİÇİM OTOPARKI',
    'Latitude': '41.01',
    'Longitude': '28.97',
    'Kapasitesi': 50,
    'BosKapasite': 10,
    'ParkTipi': 'AÇIK OTOPARK',
    'Ilce': 'FATİH',
  },
];

const isparkDetailJson = {
  'locationName': 'Taksim',
  'parkID': 1001,
  'parkName': 'TAKSİM KATLI OTOPARKI',
  'lat': '41.0372',
  'lng': '28.9861',
  'capacity': 400,
  'emptyCapacity': 118,
  'updateDate': '26.11.2026 14:05:00',
  'workHours': '24 Saat',
  'parkType': 'KAPALI OTOPARK',
  'freeTime': 15,
  'monthlyFee': 3500.0,
  'tariff': '0-1 Saat : 90 TL;1-2 Saat : 110 TL;2-4 Saat : 140 TL;0-24 Saat : 250 TL',
  'district': 'BEYOĞLU',
  'address': 'Gümüşsuyu Mah. İnönü Cad.',
  'areaPolygon': null,
};

const overpassJson = {
  'version': 0.6,
  'osm3s': {'timestamp_osm_base': '2026-11-26T10:00:00Z'},
  'elements': [
    {
      'type': 'way',
      'id': 501,
      'center': {'lat': 41.0372, 'lon': 28.9862}, // İSPARK 1001 ile aynı yer → tekrar
      'tags': {'amenity': 'parking', 'name': 'Taksim Otoparkı', 'parking': 'multi-storey'},
    },
    {
      'type': 'node',
      'id': 502,
      'lat': 41.0330,
      'lon': 28.9790,
      'tags': {
        'amenity': 'parking',
        'name': 'Tarlabaşı Açık Otopark',
        'parking': 'surface',
        'fee': 'yes',
        'charge': '60 TRY/hour; 300 TRY/day',
        'capacity': '80',
        'opening_hours': '24/7',
        'wheelchair': 'yes',
        'capacity:charging': '2',
        'addr:street': 'Tarlabaşı Bulvarı',
        'addr:housenumber': '10',
        'addr:city': 'İstanbul',
        'phone': '+90 212 000 00 00',
        'website': 'https://ornek-otopark.example',
      },
    },
    {
      'type': 'node',
      'id': 503,
      'lat': 41.0450,
      'lon': 28.9900,
      'tags': {'amenity': 'parking', 'fee': 'no', 'parking': 'street_side'},
    },
    {
      'type': 'node',
      'id': 504,
      'tags': {'amenity': 'parking'},
    }, // koordinatsız
  ],
};

const nominatimJson = [
  {'lat': '40.9909', 'lon': '29.0303', 'name': 'Kadıköy', 'display_name': 'Kadıköy, İstanbul, Marmara Bölgesi, 34710, Türkiye'},
  {'lat': 'x', 'lon': '1'},
];
