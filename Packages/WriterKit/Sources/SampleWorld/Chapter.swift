import Foundation

extension SampleWorld {
    /// "The Night the Bell Rang", a paragraph to a line, as its author typed it: straight
    /// quotes and apostrophes, two hyphens for a dash and three dots for an ellipsis, which
    /// the app sets as print does only when it shows them (`Typeset`). About 1,200 words of
    /// plain prose and dialogue in paragraphs of every length, to judge how a long page reads.
    static let chapter: [String] = """
        The glass had been falling since noon, and by dusk Mara did not need the glass to tell her anything. \
        The gulls had gone inland. The sea had the flat, oiled look it wore before it changed its mind.
        She lit the lamp early. Forty years in the lighthouse had taught her that nobody ever drowned because \
        a light was lit too soon.
        The lamp room was the one warm place on the rock. It smelled of oil and hot brass, and the windows ran \
        with wet on the inside no matter how often she wiped them down.
        "You should've gone back at four," she said.
        Jory sat on the oil crate with his knees drawn up, watching the weights of the clockwork creep down \
        their long shaft. He was thirteen and believed, as far as she could tell, that weather was something \
        that happened to other people.
        "I couldn't. The boat's leaking again."
        "The boat's always leaking."
        "More, I mean. It's leaking more." He looked up. "Is it going to be bad?"
        Mara did not answer that. She put her hand flat on the brass housing instead, the way Old Tamsin had \
        told her to, and felt for the beat of the clockwork under her palm. One, and one, and one. Steady as a \
        sleeping dog. The lamp turned above them, and its long arm of light went out over the water, came \
        round, went out again.
        "It's going to be a night," she said at last. "You'll sleep in the oil store. There's blankets."
        "I'm not tired."
        "You will be."
        The first of the wind came at seven. It did not build -- it simply arrived, all at once, like a door \
        thrown open somewhere out past the point, and the whole tower hummed with it. Rain followed, then \
        something harder than rain. Mara went round the gallery with a lantern and checked every latch twice. \
        When she came back in, her hair was soaked through and Jory had stopped pretending not to be afraid.
        "There's boats still out," he said. "I counted them going. Eleven went and I've only counted nine \
        back."
        "Then two are late."
        "The Petrel's one. She's always last. My uncle says her skipper would rather drown than lose a net."
        "Your uncle talks too much."
        "He says you never sleep, either."
        "He's right about that one."
        But she went to the seaward window all the same, and cupped her hands against the glass.
        For a long time there was nothing to see. The beam went out, and showed her rain. It came round, and \
        showed her the white tops of the seas breaking on the reef. Out, and round. Out, and round. Then, far \
        off to the north, where the cliffs ran up toward the Iron Abbey, she caught a spark of yellow that was \
        not hers.
        "There," said Jory, who had come up beside her without her hearing. "That's a masthead light. That's \
        her."
        "That's somebody."
        "She's too close in. Isn't she? She's too close to the reef."
        "Hush."
        The yellow light climbed, hung, dropped out of sight, climbed again. Mara had watched boats come home \
        to Breakwater through weather like this more times than she could count, and she knew the rhythm of it \
        the way she knew the beat of the clockwork. A boat that was making way rose and fell like breathing. \
        This one was not breathing right. It rose, and stayed too long, and when it fell it fell sideways.
        "Wind the weights," she said.
        "They're not due for an hour."
        "Wind them anyway. All the way up. I don't want that lamp stopping tonight for anything, do you \
        understand me? Not for one turn."
        He ran. She heard the ratchet begin its slow climb behind her -- click, click, click -- and she kept \
        her eyes on the yellow spark and did the only other thing there was to do, which was nothing.
        It is a hard thing to keep a light. People in the town thought it was the stairs that were hard, or \
        the cold, or the being alone. It was none of those. It was standing at a window with your hands full \
        of nothing while the sea decided.
        The spark went out.
        Not behind a wave. She knew the difference. A light that goes behind a wave is cut off from the bottom \
        up, and comes back the same way. This one simply stopped, the way a candle does when somebody has \
        finished with it.
        She waited for it to climb again. She counted the turns of the lamp: one, two, three. Four. Five.
        "Mara?" Jory's voice came from the stair, small. "I've wound it. It's right up. Mara, is she..."
        "Come away from the window."
        "But is she..."
        "I said come away."
        That was when the bell rang.
        It rang once, a full round stroke, the kind you only get when a grown man leans his whole weight on \
        the rope. Mara felt it through the floor before she heard it. The rope came down through the lamp room \
        not six feet from where she stood, through a brass-lipped hole in the boards, and she turned and \
        looked at it.
        The rope was hanging perfectly still.
        The bell rang again.
        "That's not me," Jory said. He had backed against the wall with both hands held up, open, as if she \
        might think he had it hidden somewhere. "I never touched it. Mara, I swear, I never--"
        "I know you didn't."
        "Then who's ringing it?"
        She did not have an answer, and so, for the second time that night, she did not give one. She took the \
        lantern and went out onto the gallery, into the whole roaring weight of the wind, and leaned over the \
        rail as far as she dared.
        The bell hung in its iron cradle below her, black and streaming. Nobody stood beneath it. There was \
        nowhere beneath it to stand -- only the wet rock, and then the sea. As she watched, the bell swung \
        out, slowly, against the wind and not with it, and the clapper fell.
        A third stroke. A fourth.
        She found that she was counting, and then she understood what she was counting, and she stopped being \
        cold. On this coast you rang a bell for the drowned, one stroke for each year of their age, and the \
        whole harbour stood and counted with you, so that nobody had to carry the number alone.
        Nobody was ringing this bell. And still it rang.
        Jory had come out behind her. He was holding on to the door frame with both arms, and his mouth was \
        moving. It took her a moment to hear what he was saying over the wind.
        "Fourteen," he said. "Fifteen. Sixteen."
        "Go inside."
        "Somebody has to count. You said. Somebody always has to..." His voice cracked. "Seventeen."
        Mara looked at him. Then she looked north, at the place on the black water where a yellow light had \
        been.
        "Eighteen," she said.
        He nodded, wiped his face with the back of his wrist, and went on. She put a hand on his shoulder to \
        keep him out of the wind -- or that was what she would have said, if anybody had asked.
        They counted together until the bell was finished. It took a long time.
        """.split(separator: "\n").map(String.init)
}
