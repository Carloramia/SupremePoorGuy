"""Read-only OOXML fallback for an event workbook with invalid fill styles."""
from pathlib import Path
import json
import zipfile
import xml.etree.ElementTree as ET

source = Path(r'D:\Downloads\事件 (1).xlsx')
destination = Path(__file__).parent / 'events_revision_20261007_export'
destination.mkdir(exist_ok=True)
ns = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
with zipfile.ZipFile(source) as archive:
    shared = [''.join(item.itertext()) for item in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('m:si', ns)]
    sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
    lines = ['# 新版事件表原始单元格', '', '> 来源：D:/Downloads/事件 (1).xlsx；原文件未修改。', '> 🤖[AI] 标准读取器因非法 Fill 样式失败，降级为 OOXML 文本提取；未进行视觉渲染。', '']
    formulas = []
    for row in sheet.findall('m:sheetData/m:row', ns):
        cells = []
        for cell in row.findall('m:c', ns):
            value = cell.find('m:v', ns)
            inline = cell.find('m:is', ns)
            formula = cell.find('m:f', ns)
            if formula is not None:
                formulas.append({'cell': cell.attrib['r'], 'formula': formula.text})
            if value is None and inline is None:
                continue
            text = shared[int(value.text)] if cell.attrib.get('t') == 's' else ''.join(inline.itertext()) if inline is not None else value.text or ''
            cells.append(cell.attrib['r'] + ': ' + text.replace('\n', '<br>'))
        if cells:
            lines.extend(['R' + row.attrib['r'] + '| ' + ' | '.join(cells), ''])
    lines.extend(['🤖[AI] 新版列为：事件名、概览、地点、所处阶段、对话对象、内容、奖励、效果、需要内容。', '🤖[AI] 所处阶段同时包含触发条件（D13/D54）和流程状态（D33/D35），运行配置需区分。', '🤖[AI] 血祭碑文的三/七/一是叙事表达；结构化判定应采用用户明确的飞行或快速移动、皮毛、无手且无足条件。'])
    (destination / 'data.md').write_text('\n'.join(lines), encoding='utf-8')
    (destination / 'formula_check.json').write_text(json.dumps({'method': 'OOXML fallback', 'formulas': formulas, 'media_count': len([name for name in archive.namelist() if name.startswith('xl/media/')])}, ensure_ascii=False, indent=2), encoding='utf-8')
    (destination / 'lineage_report.md').write_text('# 跨区块检查\n\n🤖[AI] 工作簿无公式。D19/G19 的“图书开门日”与 A21 的“图书馆开门日”指向可能相同但命名不一致，需统一；当前不存在机器可追踪的事件引用。\n\n🤖[AI] 血祭日文本三/七/一与用户目标 3/7/1 一致；并非公式联动，文本修改后需人工同步。\n', encoding='utf-8')
print(destination)
