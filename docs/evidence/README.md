# Evidence / 实验原始记录

Raw records from live runs of the on-device model on an Apple M2 (macOS 27.0, September 2026). Each file holds the prompts, the model's raw output, the plan, whether it was accepted and executed, and token counts. Failures are kept on purpose.

在 Apple M2（macOS 27.0，2026 年 9 月）上真调端侧模型的原始记录。每个文件包含提示词、模型原始输出、计划、是否接纳和执行、token 数。失败的也特意保留。

## v01: how much freedom the model can handle / 模型能承受多大自由度

Produced by earlier versions of the planner; the current code only uses the last approach.
由早期版本的规划代码生成；现在的代码只用最后一种做法。

| File | Setup / 设置 | Result / 结果 |
|---|---|---|
| `v01/1-verb-target-multistep.json` | Verb + target, 1–3 steps / 动词 + 目标，1–3 步 | 6 / 8 |
| `v01/2-action-enum-multistep.json` | Full action list, 1–3 steps / 完整动作列表，1–3 步 | 7 / 12 |
| `v01/3-legal-actions-single-step.json` | Only currently legal actions, one step / 只给此刻合法的动作，单步 | 16 / 16 |

## v02: short activities and expression / 短活动和表达

| File | Setup / 设置 | Result / 结果 |
|---|---|---|
| `v02/model-free-ascii.json` | Actions + free expression in one call / 动作和自由表达同一次调用 | 15 / 16 |
| `v02/model-unsupported-guide.json` | Complex regex guide / 复杂正则约束 | 0 / 4 (unsupported) |
| `v02/model-chinese-free-ascii.json` | Free-form Chinese ASCII art / 自由中文字符画 | 2 / 4 |
| `v02/model-composed-coupled.json` | Composed doodle, expression still tied to the first action / 组合画，表达仍和第一个动作绑在一起 | 2 / 4 |
| `v02/model-separated-pilot.json` | Actions and expression split, small pilot / 动作和表达分开，小样本 | 4 / 4 |
| `v02/model-separated-continuous.json` | Split, continuous session / 分开后的连续一局 | 16 / 16 |
| `v02/model-final-continuous.json` | Final version, with recent activity titles / 最终版，加入最近活动标题 | 16 / 16 |

In the continuous runs the box is moved at round 5, the ball taken at round 9 and returned at round 13.
连续实验在第 5 轮搬箱子、第 9 轮拿走球、第 13 轮放回球。
