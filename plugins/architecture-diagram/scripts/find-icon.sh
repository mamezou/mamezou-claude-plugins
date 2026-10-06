#!/usr/bin/env bash
# 手元の Draw.io Desktop に入っているアイコンの名前を検索する。
# 使い方: find-icon.sh <aws|azure> <語>
# 出力: aws は「resIcon=... または shape=...」「パレットでの表示名」「カテゴリ」のタブ区切り、
#       azure は img/lib/azure2/ に続けて書くパス。見つからなければ no match
# 環境変数: DRAWIO_ASAR (Draw.io 本体の app.asar のパス。指定すると drawio コマンドは不要)
#           未指定のときは、drawio コマンドの実体の場所から app.asar を探す
# aws の検索は Draw.io の Sidebar-AWS4.js の書式を読む。Draw.io の版が変わって定義を読めなくなったら、ここの正規表現を見直す
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <aws|azure> <keyword>" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 was not found." >&2
  exit 1
fi

asar_path=${DRAWIO_ASAR:-}
if [ -z "$asar_path" ]; then
  if ! command -v drawio >/dev/null 2>&1; then
    echo "drawio was not found. Set DRAWIO_ASAR to the path of app.asar." >&2
    exit 1
  fi
  drawio_dir=$(python3 -c 'import os, sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "$(command -v drawio)")
  for candidate in \
    "$drawio_dir/resources/app.asar" \
    "$drawio_dir/../Resources/app.asar" \
    "/Applications/draw.io.app/Contents/Resources/app.asar"; do
    if [ -f "$candidate" ]; then
      asar_path=$candidate
      break
    fi
  done
  if [ -z "$asar_path" ]; then
    echo "app.asar was not found near $drawio_dir. Set DRAWIO_ASAR to the path of app.asar." >&2
    exit 1
  fi
elif [ ! -f "$asar_path" ]; then
  echo "app.asar was not found: $asar_path (check DRAWIO_ASAR)" >&2
  exit 1
fi

python3 - "$asar_path" "$1" "$2" <<'PY'
import json
import re
import signal
import struct
import sys

# 出力を head などへ渡して途中で閉じられても、エラーを出さずに終わる
if hasattr(signal, 'SIGPIPE'):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

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
    # app.asar の外に置かれたファイル(unpacked、link)は読めない
    if 'offset' not in entry or entry.get('unpacked'):
        return ''
    archive.seek(base + int(entry['offset']))
    return archive.read(entry['size']).decode('utf-8', 'replace')


hits = []
definitions = 0
if kind == 'azure':
    # 出力: style の image=img/lib/azure2/ に続けて書くパス
    for path, entry in walk(header):
        if '/img/lib/azure2/' in path and path.endswith('.svg'):
            definitions += 1
            relative = path.split('/img/lib/azure2/')[1]
            if keyword in relative.lower():
                hits.append(relative)
elif kind == 'aws':
    # 出力: style に書く指定、Draw.io のパレットでの表示名、カテゴリ
    categories = {
        'ARVR': 'AR & VR', 'Analytics': 'Analytics', 'ApplicationIntegration': 'Application Integration',
        'ArtificialIntelligence': 'Artificial Intelligence', 'Blockchain': 'Blockchain',
        'BusinessApplications': 'Business Applications', 'CloudFinancialManagement': 'Cloud Financial Management',
        'Compute': 'Compute', 'ContactCenter': 'Contact Center', 'Containers': 'Containers',
        'CustomerEnablement': 'Customer Enablement', 'CustomerEngagement': 'Customer Engagement',
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
                    # 図形名として使えない形(= を含むなど)は出さない
                    if not re.fullmatch(r'[a-z0-9_]+', name):
                        continue
                    definitions += 1
                    if keyword in name.lower() or keyword in title.lower().replace(' ', '_'):
                        key = 'resIcon' if shape_kind == 'resourceIcon' else 'shape'
                        hits.append(f'{key}=mxgraph.aws4.{name}\t{title.strip()}\t{category}')
else:
    sys.exit('The first argument must be aws or azure.')

if definitions == 0:
    sys.exit(f'No {kind} icon definitions were found in {asar_path}. The Draw.io version may use a different layout.')

print('\n'.join(sorted(set(hits))) if hits else 'no match')
PY
