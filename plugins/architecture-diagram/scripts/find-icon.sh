#!/usr/bin/env bash
# 手元の Draw.io Desktop に入っているアイコンの名前を検索する。
# 使い方: find-icon.sh <aws|azure> <語>
# 出力: aws は「resIcon=... または shape=...」「パレットでの表示名」「カテゴリ」のタブ区切り、
#       azure は img/lib/azure2/ に続けて書くパス。見つからなければ no match
# 環境変数: DRAWIO_ASAR (既定は drawio コマンドの実体と同じ場所の resources/app.asar)
# aws の検索は Draw.io の Sidebar-AWS4.js の書式を読む。Draw.io の版が変わって何も出なくなったら、ここの正規表現を見直す
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <aws|azure> <keyword>" >&2
  exit 2
fi

for cmd in drawio python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd was not found." >&2
    exit 1
  fi
done

asar_path=${DRAWIO_ASAR:-$(dirname "$(readlink -f "$(command -v drawio)")")/resources/app.asar}
if [ ! -f "$asar_path" ]; then
  echo "app.asar was not found: $asar_path (set DRAWIO_ASAR)" >&2
  exit 1
fi

python3 - "$asar_path" "$1" "$2" <<'PY'
import json
import re
import struct
import sys

asar_path, kind, keyword = sys.argv[1], sys.argv[2], sys.argv[3].lower().replace(' ', '_')

archive = open(asar_path, 'rb')
archive.seek(4)
header_size = struct.unpack('<I', archive.read(4))[0]
archive.seek(12)
json_size = struct.unpack('<I', archive.read(4))[0]
header = json.loads(archive.read(json_size))
base = 8 + header_size


def walk(node, path=''):
    for name, entry in node.get('files', {}).items():
        child = path + '/' + name
        if 'files' in entry:
            yield from walk(entry, child)
        else:
            yield child, entry


def read(entry):
    archive.seek(base + int(entry['offset']))
    return archive.read(entry['size']).decode('utf-8', 'replace')


hits = []
if kind == 'azure':
    # 出力: style の image=img/lib/azure2/ に続けて書くパス
    for path, entry in walk(header):
        if '/img/lib/azure2/' in path and path.endswith('.svg'):
            relative = path.split('/img/lib/azure2/')[1]
            if keyword in relative.lower():
                hits.append(relative)
elif kind == 'aws':
    # 出力: style に書く指定、Draw.io のパレットでの表示名、カテゴリ
    categories = {
        'Analytics': 'Analytics', 'ApplicationIntegration': 'Application Integration',
        'ArtificialIntelligence': 'Artificial Intelligence', 'Blockchain': 'Blockchain',
        'BusinessApplications': 'Business Applications', 'CloudFinancialManagement': 'Cloud Financial Management',
        'Compute': 'Compute', 'Containers': 'Containers', 'CustomerEnablement': 'Customer Enablement',
        'Database': 'Databases', 'DeveloperTools': 'Developer Tools', 'EndUserComputing': 'End User Computing',
        'FrontEndWebMobile': 'Front-End Web & Mobile', 'Games': 'Games', 'GeneralResources': 'General',
        'InternetOfThings': 'Internet of Things', 'ManagementGovernance': 'Management & Governance',
        'MediaServices': 'Media Services', 'MigrationModernization': 'Migration & Modernization',
        'NetworkContentDelivery': 'Networking & Content Delivery', 'QuantumTechnologies': 'Quantum Technologies',
        'Satellite': 'Satellite', 'SecurityIdentityCompliance': 'Security, Identity & Compliance', 'Storage': 'Storage',
    }
    section = re.compile(r'addAWS4([A-Za-z0-9]+)Palette = function')
    entry_pattern = re.compile(
        r"createVertexTemplateEntry\(\w+ \+ '([^']*)'(?: \+ gn \+ '\.([^';]*);?[^']*')?,"
        r"\s*[^,]+,[^,]+,\s*'[^']*',\s*'([^']*)'"
    )
    for path, entry in walk(header):
        if path.endswith('/sidebar/Sidebar-AWS4.js'):
            source = read(entry)
            starts = [(m.start(), m.group(1)) for m in section.finditer(source)]
            for index, (start, raw_category) in enumerate(starts):
                end = starts[index + 1][0] if index + 1 < len(starts) else len(source)
                category = categories.get(raw_category, raw_category)
                for prefix, name, title in entry_pattern.findall(source[start:end]):
                    if name:
                        shape_kind = prefix.split(';')[0]
                    else:
                        shape_kind, name = 'shape', prefix.split(';')[0]
                    if shape_kind not in ('resourceIcon', 'shape'):
                        continue
                    if keyword in name.lower() or keyword in title.lower().replace(' ', '_'):
                        key = 'resIcon' if shape_kind == 'resourceIcon' else 'shape'
                        hits.append(f'{key}=mxgraph.aws4.{name}\t{title.strip()}\t{category}')
else:
    sys.exit('The first argument must be aws or azure.')

print('\n'.join(sorted(set(hits))) if hits else 'no match')
PY
