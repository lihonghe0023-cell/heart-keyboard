九宫格词库说明
================

t9.dict / t9.initials / t9.chain / t9.syllable 由 work/build-t9.mjs 生成，
数据来源：

  Rime 简体拼音词库 (rime-pinyin-simp)
  https://github.com/rime/rime-pinyin-simp
  许可证：Apache License 2.0（完整文本见 LICENSE-pinyin_simp.txt）
  上游：Android Open Source Project PinyinIME 词库

生成后的文件格式（全部按第一列排序，可直接二分查找）：

  t9.dict      digits  <tab> initials <tab> word <tab> weight <tab> pinyin
  t9.initials  initials<tab> digits   <tab> word <tab> weight
  t9.chain     char    <tab> word|word|...        尾字联想
  t9.syllable  digits  <tab> word|word|...        首音节联想

重新生成：

  node work/build-t9.mjs

改词库（加自己的行业词、口头禅）就直接改生成脚本里的数据源，再跑一次。
