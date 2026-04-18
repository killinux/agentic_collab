"""
Quick demo: generate a multi-turn Chinese conversation between Isabella
and Klaus using the real prompt pipeline. Run from backend_server/:

    python3 demo_zh_chat.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from persona.prompt_template.gpt_structure import ChatGPT_safe_generate_structured_response
from persona.prompt_template.v3_ChatGPT.iterative_convo_v1 import ChatUtterance, create_prompt

ISABELLA = "Isabella Rodriguez 是 Hobbs Cafe 的老板,友善外向,喜欢让顾客有宾至如归的感觉。她在筹备 2 月 14 日下午 5 点的情人节派对。"
KLAUS = "Klaus Mueller 是 Oak Hill 学院社会学学生,正在写一篇关于士绅化的研究论文。"

def gen(speaker_name, listener_name, speaker_iss, listener_iss, convo_so_far, situation):
    prompt_input = {
        "identity_stable_set": speaker_iss,
        "init_persona_name": speaker_name,
        "retrieved_memories": f"- {listener_iss}\n",
        "prev_conversation": "",
        "curr_location": "counter at Hobbs Cafe",
        "curr_situation": situation,
        "target_persona_name": listener_name,
        "curr_conversation": convo_so_far if convo_so_far else "[The conversation has not started yet -- start it!]",
    }
    prompt = create_prompt(prompt_input)

    def validate(resp, prompt=""): return isinstance(resp, ChatUtterance)
    def clean(resp, prompt=""): return {"utterance": resp.utterance, "end": resp.did_conversation_end}
    fail_safe = {"utterance": "...", "end": False}
    return ChatGPT_safe_generate_structured_response(
        prompt, ChatUtterance, repeat=3,
        fail_safe_response=fail_safe, func_validate=validate, func_clean_up=clean,
    )

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("  DEMO: 伊莎贝拉 ↔ 克劳斯 在 Hobbs Cafe 的对话")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

convo = []
current_speaker = "Isabella Rodriguez"
situation = "Klaus 走进 Hobbs Cafe,看起来有点累。Isabella 在柜台后面招呼他。"
for turn in range(6):
    if current_speaker == "Isabella Rodriguez":
        me, you, me_iss, you_iss = "Isabella Rodriguez", "Klaus Mueller", ISABELLA, KLAUS
    else:
        me, you, me_iss, you_iss = "Klaus Mueller", "Isabella Rodriguez", KLAUS, ISABELLA

    convo_str = "\n".join(f"{s}: {u}" for s,u in convo)
    result = gen(me, you, me_iss, you_iss, convo_str, situation)
    utt = result["utterance"]
    ended = result["end"]

    marker = "   " if me == "Klaus Mueller" else ""
    print(f"\n  {marker}{me}:\n  {marker}  {utt}")

    convo.append((me, utt))
    if ended:
        print("\n  [conversation ended]")
        break
    current_speaker = you

print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  总轮数: {len(convo)}")
