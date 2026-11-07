// Bro’s Fitness food database. Values are per 100 g (or 100 ml for liquids), cooked/ready-to-eat unless noted.
// Sources: averages from the Indian Food Composition Tables (IFCT 2017, NIN) and USDA FoodData Central.
// Home-cooked Kerala dishes vary with oil, coconut and recipe — those values are typical estimates and are labelled as such.

export interface Food {
  id: string;
  name: string;
  cat: 'Kerala & South Indian' | 'Indian' | 'Grains & breads' | 'Protein' | 'Dairy' | 'Fruits' | 'Vegetables' | 'Nuts & seeds' | 'Legumes' | 'Fats & oils' | 'Drinks' | 'Snacks & sweets';
  kcal: number; p: number; c: number; f: number; fib: number;
  unit?: 'g' | 'ml';
  servings: { label: string; g: number }[];
  aliases?: string[];
  estimate?: boolean; // recipe-dependent dish
  custom?: boolean;
}

const f = (
  id: string, name: string, cat: Food['cat'], kcal: number, p: number, c: number, fat: number, fib: number,
  servings: [string, number][], aliases: string[] = [], extra: Partial<Food> = {},
): Food => ({ id, name, cat, kcal, p, c, f: fat, fib, servings: servings.map(([label, g]) => ({ label, g })), aliases, ...extra });

const E = { estimate: true };
const ML = { unit: 'ml' as const };

export const FOODS: Food[] = [
  // Kerala & South Indian
  f('rice-white', 'Rice, white (cooked)', 'Grains & breads', 130, 2.7, 28.2, 0.3, 0.4, [['1 cup', 160], ['1 plate', 250]], ['rice', 'choru', 'chor', 'white rice', 'boiled rice']),
  f('rice-matta', 'Kerala matta / red rice (cooked)', 'Kerala & South Indian', 123, 2.6, 26.5, 0.5, 1.2, [['1 cup', 160], ['1 plate', 250]], ['matta rice', 'red rice', 'rosematta', 'kuthari']),
  f('rice-brown', 'Rice, brown (cooked)', 'Grains & breads', 112, 2.3, 23.5, 0.8, 1.8, [['1 cup', 160]], ['brown rice']),
  f('rice-basmati', 'Basmati rice (cooked)', 'Grains & breads', 121, 3.5, 25.2, 0.4, 0.4, [['1 cup', 160]], ['basmati']),
  f('puttu', 'Puttu (rice)', 'Kerala & South Indian', 165, 3.0, 34.5, 1.6, 1.5, [['1 piece (cylinder)', 120], ['1 cup', 100]], ['puttu', 'rice puttu', 'arikkal puttu'], E),
  f('appam', 'Appam / palappam', 'Kerala & South Indian', 196, 3.4, 37.5, 3.6, 1.0, [['1 appam', 50]], ['appam', 'appams', 'palappam', 'vellayappam'], E),
  f('idiyappam', 'Idiyappam (string hoppers)', 'Kerala & South Indian', 150, 2.6, 33.5, 0.4, 0.8, [['1 piece', 40]], ['idiyappam', 'noolputtu', 'string hopper'], E),
  f('dosa', 'Dosa, plain', 'Kerala & South Indian', 168, 3.9, 29.0, 3.7, 1.0, [['1 dosa', 80]], ['dosa', 'dosai', 'dosas', 'plain dosa'], E),
  f('masala-dosa', 'Masala dosa', 'Kerala & South Indian', 180, 3.5, 26.0, 7.0, 2.0, [['1 masala dosa', 160]], ['masala dosa'], E),
  f('idli', 'Idli', 'Kerala & South Indian', 130, 4.0, 27.0, 0.4, 1.5, [['1 idli', 40]], ['idli', 'idly', 'idlis', 'idlies']),
  f('upma', 'Upma (rava)', 'Kerala & South Indian', 150, 3.5, 22.0, 5.0, 1.5, [['1 cup', 180]], ['upma', 'uppumavu'], E),
  f('kappa', 'Tapioca / kappa (boiled)', 'Kerala & South Indian', 135, 1.0, 33.0, 0.3, 1.8, [['1 cup', 150], ['1 plate', 250]], ['kappa', 'tapioca', 'cassava', 'kappa puzhukku']),
  f('kerala-parotta', 'Kerala parotta', 'Kerala & South Indian', 330, 7.0, 45.0, 13.0, 1.5, [['1 parotta', 80]], ['parotta', 'porotta', 'paratha', 'barotta', 'porottas'], E),
  f('sambar', 'Sambar', 'Kerala & South Indian', 65, 3.0, 9.0, 2.0, 2.5, [['1 bowl', 150], ['1 ladle', 75]], ['sambar', 'sambhar'], E),
  f('avial', 'Avial', 'Kerala & South Indian', 110, 2.5, 8.0, 7.5, 3.0, [['1 serving', 100]], ['avial', 'aviyal'], E),
  f('thoran', 'Thoran, cabbage', 'Kerala & South Indian', 95, 2.0, 7.0, 6.5, 2.8, [['1 serving', 80]], ['thoran', 'cabbage thoran', 'beans thoran', 'mezhukkupuratti'], E),
  f('kadala-curry', 'Kadala curry (black chickpea)', 'Kerala & South Indian', 140, 6.5, 16.0, 5.5, 5.0, [['1 bowl', 150]], ['kadala', 'kadala curry', 'black chana curry', 'chana curry'], E),
  f('fish-curry', 'Kerala fish curry (with fish)', 'Kerala & South Indian', 120, 13.0, 4.0, 6.0, 0.8, [['1 bowl', 150]], ['fish curry', 'meen curry', 'meen'], E),
  f('fish-fry', 'Fish fry, Kerala style (sardine/mackerel)', 'Kerala & South Indian', 220, 22.0, 4.0, 13.0, 0.5, [['1 piece', 60]], ['fish fry', 'meen fry', 'meen varuthathu', 'fried fish', 'mathi fry', 'ayala fry'], E),
  f('chicken-curry', 'Chicken curry, Kerala style', 'Kerala & South Indian', 160, 14.0, 5.0, 9.5, 1.0, [['1 bowl', 150]], ['chicken curry', 'kozhi curry'], E),
  f('beef-fry', 'Beef ularthiyathu (Kerala beef fry)', 'Kerala & South Indian', 250, 22.0, 5.0, 16.0, 1.0, [['1 serving', 100]], ['beef fry', 'beef ularthiyathu', 'beef roast'], E),
  f('egg-roast', 'Egg roast, Kerala style', 'Kerala & South Indian', 170, 9.0, 6.0, 12.0, 1.0, [['1 egg with masala', 90]], ['egg roast', 'mutta roast'], E),
  f('chicken-biryani', 'Chicken biryani (Kerala/Malabar)', 'Kerala & South Indian', 180, 8.0, 22.0, 6.5, 0.8, [['1 plate', 350]], ['biryani', 'chicken biryani', 'malabar biryani'], E),
  f('ghee-rice', 'Ghee rice', 'Kerala & South Indian', 200, 3.0, 30.0, 7.5, 0.5, [['1 plate', 250]], ['ghee rice', 'neychoru'], E),
  f('coconut-chutney', 'Coconut chutney', 'Kerala & South Indian', 230, 3.0, 9.0, 21.0, 5.0, [['1 tbsp', 20], ['1 serving', 40]], ['chutney', 'coconut chutney'], E),
  f('pazham-pori', 'Pazham pori (banana fritter)', 'Snacks & sweets', 280, 3.0, 40.0, 12.0, 1.5, [['1 piece', 60]], ['pazham pori', 'ethakka appam', 'banana fritter'], E),
  f('unniyappam', 'Unniyappam', 'Snacks & sweets', 320, 3.5, 50.0, 12.0, 2.0, [['1 piece', 25]], ['unniyappam'], E),
  f('payasam', 'Payasam (semiya/vermicelli)', 'Snacks & sweets', 150, 3.5, 24.0, 4.5, 0.3, [['1 cup', 150]], ['payasam', 'kheer'], E),
  f('medu-vada', 'Medu vada (uzhunnu vada)', 'Snacks & sweets', 300, 9.0, 28.0, 17.0, 4.0, [['1 vada', 45]], ['vada', 'uzhunnu vada', 'medu vada'], E),
  f('banana-nendran', 'Banana, nendran (Kerala)', 'Fruits', 116, 1.2, 28.0, 0.3, 2.0, [['1 medium', 150]], ['nendran', 'nendran banana', 'ethapazham', 'ethakka']),
  f('jackfruit', 'Jackfruit (ripe)', 'Fruits', 95, 1.7, 23.2, 0.6, 1.5, [['5 bulbs', 100]], ['jackfruit', 'chakka', 'chakkapazham']),
  f('moru', 'Buttermilk / moru (diluted)', 'Drinks', 18, 0.9, 1.5, 0.8, 0, [['1 glass', 250]], ['buttermilk', 'moru', 'chaas', 'sambharam'], ML),

  // Indian
  f('chapati', 'Chapati / roti (whole wheat)', 'Indian', 264, 8.7, 48.0, 3.7, 4.9, [['1 chapati', 40]], ['chapati', 'chapathi', 'roti', 'phulka', 'chapatis', 'chapathis', 'rotis']),
  f('dal', 'Dal (toor/moong, cooked with tadka)', 'Indian', 120, 6.5, 15.0, 4.0, 3.5, [['1 bowl', 150]], ['dal', 'dhal', 'parippu', 'lentil curry', 'daal'], E),
  f('paneer', 'Paneer', 'Dairy', 265, 18.3, 1.2, 20.8, 0, [['1 cube (25 g)', 25], ['100 g', 100]], ['paneer', 'cottage cheese']),
  f('mutton-curry', 'Mutton curry', 'Indian', 200, 15.0, 4.0, 14.0, 1.0, [['1 bowl', 150]], ['mutton curry', 'mutton', 'goat curry'], E),
  f('rajma', 'Rajma (kidney beans, cooked)', 'Legumes', 127, 8.7, 22.8, 0.5, 6.4, [['1 bowl', 150]], ['rajma', 'kidney beans']),
  f('samosa', 'Samosa', 'Snacks & sweets', 308, 5.0, 32.0, 18.0, 2.5, [['1 samosa', 60]], ['samosa'], E),
  f('poha', 'Poha', 'Indian', 130, 2.5, 23.0, 3.0, 1.0, [['1 plate', 180]], ['poha', 'aval'], E),
  f('khichdi', 'Khichdi', 'Indian', 120, 4.0, 20.0, 2.5, 2.0, [['1 bowl', 200]], ['khichdi'], E),

  // Grains & breads
  f('oats', 'Oats, rolled (dry)', 'Grains & breads', 389, 16.9, 66.3, 6.9, 10.6, [['1/2 cup', 40]], ['oats', 'oatmeal', 'porridge oats']),
  f('bread-white', 'Bread, white', 'Grains & breads', 265, 9.0, 49.0, 3.2, 2.7, [['1 slice', 25]], ['bread', 'white bread', 'slice']),
  f('bread-wheat', 'Bread, whole wheat / brown', 'Grains & breads', 247, 13.0, 41.0, 3.4, 7.0, [['1 slice', 28]], ['brown bread', 'wheat bread', 'whole wheat bread']),
  f('cornflakes', 'Cornflakes', 'Grains & breads', 357, 7.5, 84.0, 0.4, 3.3, [['1 bowl', 30]], ['cornflakes', 'cereal']),
  f('pasta', 'Pasta (cooked)', 'Grains & breads', 158, 5.8, 30.9, 0.9, 1.8, [['1 cup', 140]], ['pasta', 'spaghetti', 'macaroni']),
  f('potato', 'Potato (boiled)', 'Vegetables', 87, 1.9, 20.1, 0.1, 1.8, [['1 medium', 150]], ['potato', 'aloo', 'urulakizhangu']),
  f('sweet-potato', 'Sweet potato (boiled)', 'Vegetables', 76, 1.4, 17.7, 0.1, 2.5, [['1 medium', 130]], ['sweet potato', 'madhurakizhangu']),

  // Protein
  f('egg', 'Egg, whole (boiled)', 'Protein', 155, 12.6, 1.1, 10.6, 0, [['1 large egg', 50]], ['egg', 'eggs', 'boiled egg', 'mutta', 'whole egg']),
  f('egg-white', 'Egg white', 'Protein', 52, 10.9, 0.7, 0.2, 0, [['1 egg white', 33]], ['egg white', 'egg whites']),
  f('omelette', 'Omelette (with a little oil)', 'Protein', 154, 10.6, 0.6, 11.7, 0, [['2-egg omelette', 120]], ['omelette', 'omelet', 'mutta omelette'], E),
  f('chicken-breast', 'Chicken breast (grilled/cooked, skinless)', 'Protein', 165, 31.0, 0, 3.6, 0, [['1 breast', 150], ['100 g', 100]], ['chicken breast', 'grilled chicken', 'boiled chicken', 'chicken']),
  f('chicken-thigh', 'Chicken thigh (cooked, skinless)', 'Protein', 209, 26.0, 0, 10.9, 0, [['1 thigh', 90]], ['chicken thigh', 'chicken leg']),
  f('beef-lean', 'Beef, lean (cooked)', 'Protein', 217, 26.1, 0, 11.8, 0, [['100 g', 100]], ['beef', 'lean beef', 'beef steak']),
  f('fish-white', 'Fish, white (steamed/grilled)', 'Protein', 110, 23.0, 0, 1.8, 0, [['1 fillet', 120]], ['fish', 'grilled fish', 'steamed fish', 'tilapia', 'seer fish', 'neymeen']),
  f('sardine', 'Sardine / mathi (cooked, no oil)', 'Protein', 185, 24.6, 0, 9.8, 0, [['3 fish', 90]], ['sardine', 'mathi', 'chaala']),
  f('tuna', 'Tuna, canned in water', 'Protein', 116, 25.5, 0, 0.8, 0, [['1 can (drained)', 120]], ['tuna']),
  f('prawns', 'Prawns / chemmeen (cooked)', 'Protein', 99, 24.0, 0.2, 0.3, 0, [['100 g', 100]], ['prawns', 'shrimp', 'chemmeen', 'konju']),
  f('tofu', 'Tofu, firm', 'Protein', 144, 17.3, 2.8, 8.7, 2.3, [['100 g', 100]], ['tofu']),
  f('soya-chunks', 'Soya chunks (dry)', 'Protein', 345, 52.0, 33.0, 0.5, 13.0, [['1/2 cup dry', 30]], ['soya chunks', 'soya', 'meal maker', 'soy chunks']),
  f('whey', 'Whey protein powder', 'Protein', 400, 78.0, 8.0, 6.0, 0, [['1 scoop', 30]], ['whey', 'protein shake', 'protein powder', 'whey protein', 'scoop']),

  // Dairy
  f('milk-toned', 'Milk, toned (3% fat)', 'Dairy', 58, 3.1, 4.7, 3.0, 0, [['1 glass', 250], ['1 cup', 200]], ['milk', 'toned milk', 'paal'], ML),
  f('milk-full', 'Milk, full cream', 'Dairy', 88, 3.2, 4.9, 6.0, 0, [['1 glass', 250]], ['full cream milk', 'whole milk', 'buffalo milk'], ML),
  f('milk-skim', 'Milk, skimmed', 'Dairy', 35, 3.4, 5.0, 0.1, 0, [['1 glass', 250]], ['skim milk', 'skimmed milk'], ML),
  f('curd', 'Curd / dahi (whole milk)', 'Dairy', 60, 3.1, 4.4, 3.3, 0, [['1 cup', 150], ['1 bowl', 100]], ['curd', 'dahi', 'thairu', 'yogurt', 'yoghurt']),
  f('greek-yogurt', 'Greek yoghurt, plain (low-fat)', 'Dairy', 73, 9.9, 3.9, 2.0, 0, [['1 cup', 170], ['100 g', 100]], ['greek yogurt', 'greek yoghurt', 'hung curd']),
  f('cheese', 'Cheese (processed slice)', 'Dairy', 330, 18.0, 6.0, 26.0, 0, [['1 slice', 20]], ['cheese', 'cheese slice']),

  // Fruits
  f('banana', 'Banana (robusta/regular)', 'Fruits', 89, 1.1, 22.8, 0.3, 2.6, [['1 medium', 118]], ['banana', 'pazham', 'bananas']),
  f('apple', 'Apple', 'Fruits', 52, 0.3, 13.8, 0.2, 2.4, [['1 medium', 180]], ['apple', 'apples']),
  f('orange', 'Orange', 'Fruits', 47, 0.9, 11.8, 0.1, 2.4, [['1 medium', 130]], ['orange', 'oranges']),
  f('mango', 'Mango', 'Fruits', 60, 0.8, 15.0, 0.4, 1.6, [['1 cup sliced', 165]], ['mango', 'manga']),
  f('papaya', 'Papaya', 'Fruits', 43, 0.5, 10.8, 0.3, 1.7, [['1 cup', 145]], ['papaya', 'kappalanga', 'omakka']),
  f('watermelon', 'Watermelon', 'Fruits', 30, 0.6, 7.6, 0.2, 0.4, [['1 cup', 150]], ['watermelon']),
  f('guava', 'Guava', 'Fruits', 68, 2.6, 14.3, 1.0, 5.4, [['1 medium', 100]], ['guava', 'pera']),
  f('pineapple', 'Pineapple', 'Fruits', 50, 0.5, 13.1, 0.1, 1.4, [['1 cup', 165]], ['pineapple', 'kaitha chakka']),
  f('grapes', 'Grapes', 'Fruits', 69, 0.7, 18.1, 0.2, 0.9, [['1 cup', 150]], ['grapes', 'munthiri']),
  f('dates', 'Dates', 'Fruits', 277, 1.8, 75.0, 0.2, 6.7, [['1 date', 8]], ['dates', 'date', 'eenthapazham', 'khajoor']),
  f('pomegranate', 'Pomegranate', 'Fruits', 83, 1.7, 18.7, 1.2, 4.0, [['1 cup arils', 175]], ['pomegranate', 'mathalanaranga']),

  // Vegetables
  f('spinach', 'Spinach (cooked)', 'Vegetables', 23, 2.9, 3.8, 0.3, 2.4, [['1 cup', 180]], ['spinach', 'cheera', 'palak']),
  f('broccoli', 'Broccoli', 'Vegetables', 34, 2.8, 6.6, 0.4, 2.6, [['1 cup', 90]], ['broccoli']),
  f('carrot', 'Carrot', 'Vegetables', 41, 0.9, 9.6, 0.2, 2.8, [['1 medium', 60]], ['carrot', 'carrots']),
  f('tomato', 'Tomato', 'Vegetables', 18, 0.9, 3.9, 0.2, 1.2, [['1 medium', 120]], ['tomato', 'tomatoes', 'thakkali']),
  f('cucumber', 'Cucumber', 'Vegetables', 15, 0.7, 3.6, 0.1, 0.5, [['1 cup', 120]], ['cucumber', 'vellarikka']),
  f('onion', 'Onion', 'Vegetables', 40, 1.1, 9.3, 0.1, 1.7, [['1 medium', 110]], ['onion', 'savala', 'ulli']),
  f('beans-green', 'Green beans', 'Vegetables', 31, 1.8, 7.0, 0.2, 2.7, [['1 cup', 110]], ['beans', 'green beans']),
  f('okra', 'Okra / vendakka', 'Vegetables', 33, 1.9, 7.5, 0.2, 3.2, [['1 cup', 100]], ['okra', 'vendakka', 'bhindi', 'ladies finger']),
  f('cabbage', 'Cabbage', 'Vegetables', 25, 1.3, 5.8, 0.1, 2.5, [['1 cup', 90]], ['cabbage']),
  f('salad', 'Mixed green salad (no dressing)', 'Vegetables', 20, 1.3, 3.5, 0.2, 1.8, [['1 bowl', 100]], ['salad', 'vegetables', 'veggies', 'mixed vegetables'], E),

  // Legumes
  f('chickpeas', 'Chickpeas / chana (cooked)', 'Legumes', 164, 8.9, 27.4, 2.6, 7.6, [['1 cup', 160]], ['chickpeas', 'chana', 'kabuli chana', 'kadala']),
  f('moong', 'Green gram / cherupayar (cooked)', 'Legumes', 105, 7.0, 19.1, 0.4, 7.6, [['1 cup', 200]], ['green gram', 'cherupayar', 'moong', 'mung beans']),
  f('sprouts', 'Moong sprouts (raw)', 'Legumes', 30, 3.0, 5.9, 0.2, 1.8, [['1 cup', 100]], ['sprouts', 'moong sprouts']),

  // Nuts & seeds
  f('almonds', 'Almonds', 'Nuts & seeds', 579, 21.2, 21.6, 49.9, 12.5, [['10 almonds', 12], ['1 handful', 28]], ['almonds', 'badam', 'almond']),
  f('peanuts', 'Peanuts (roasted)', 'Nuts & seeds', 585, 24.0, 21.5, 49.7, 8.0, [['1 handful', 30]], ['peanuts', 'kadala', 'groundnut', 'nilakadala']),
  f('cashews', 'Cashews', 'Nuts & seeds', 553, 18.2, 30.2, 43.9, 3.3, [['10 cashews', 15], ['1 handful', 28]], ['cashew', 'cashews', 'kashuvandi', 'kaju']),
  f('walnuts', 'Walnuts', 'Nuts & seeds', 654, 15.2, 13.7, 65.2, 6.7, [['5 halves', 10], ['1 handful', 28]], ['walnut', 'walnuts']),
  f('peanut-butter', 'Peanut butter', 'Nuts & seeds', 588, 25.0, 20.0, 50.0, 6.0, [['1 tbsp', 16]], ['peanut butter', 'pb']),
  f('coconut', 'Coconut, fresh grated', 'Nuts & seeds', 354, 3.3, 15.2, 33.5, 9.0, [['1 tbsp', 8], ['1/4 cup', 20]], ['coconut', 'thenga', 'grated coconut']),
  f('chia', 'Chia seeds', 'Nuts & seeds', 486, 16.5, 42.1, 30.7, 34.4, [['1 tbsp', 12]], ['chia', 'chia seeds']),
  f('flaxseed', 'Flaxseeds', 'Nuts & seeds', 534, 18.3, 28.9, 42.2, 27.3, [['1 tbsp', 10]], ['flax', 'flaxseed', 'flax seeds', 'alsi']),

  // Fats & oils
  f('coconut-oil', 'Coconut oil', 'Fats & oils', 892, 0, 0, 99.1, 0, [['1 tsp', 4.5], ['1 tbsp', 13.6]], ['coconut oil', 'velichenna', 'oil']),
  f('ghee', 'Ghee', 'Fats & oils', 900, 0, 0, 99.8, 0, [['1 tsp', 5], ['1 tbsp', 14]], ['ghee', 'neyyu']),
  f('olive-oil', 'Olive oil', 'Fats & oils', 884, 0, 0, 100, 0, [['1 tsp', 4.5], ['1 tbsp', 13.5]], ['olive oil']),
  f('butter', 'Butter', 'Fats & oils', 717, 0.9, 0.1, 81.1, 0, [['1 tsp', 5]], ['butter']),

  // Drinks
  f('tea-milk', 'Tea with milk & sugar', 'Drinks', 40, 1.2, 6.0, 1.2, 0, [['1 cup', 150]], ['tea', 'chai', 'chaya', 'milk tea'], { ...ML, estimate: true }),
  f('coffee-milk', 'Coffee with milk & sugar', 'Drinks', 42, 1.3, 6.2, 1.3, 0, [['1 cup', 150]], ['coffee', 'kaapi', 'filter coffee'], { ...ML, estimate: true }),
  f('black-coffee', 'Black coffee (no sugar)', 'Drinks', 2, 0.3, 0, 0, 0, [['1 cup', 200]], ['black coffee', 'americano'], ML),
  f('orange-juice', 'Orange juice (fresh)', 'Drinks', 45, 0.7, 10.4, 0.2, 0.2, [['1 glass', 250]], ['orange juice', 'juice'], ML),
  f('coconut-water', 'Tender coconut water', 'Drinks', 19, 0.7, 3.7, 0.2, 1.1, [['1 coconut', 250]], ['coconut water', 'tender coconut', 'karikku', 'elaneer'], ML),
  f('soft-drink', 'Soft drink / cola', 'Drinks', 42, 0, 10.6, 0, 0, [['1 can', 330]], ['coke', 'cola', 'soda', 'soft drink', 'pepsi'], ML),

  // Snacks & sweets
  f('sugar', 'Sugar', 'Snacks & sweets', 387, 0, 100, 0, 0, [['1 tsp', 4]], ['sugar', 'panchasara']),
  f('honey', 'Honey', 'Snacks & sweets', 304, 0.3, 82.4, 0, 0.2, [['1 tsp', 7], ['1 tbsp', 21]], ['honey', 'then']),
  f('banana-chips', 'Banana chips (Kerala)', 'Snacks & sweets', 520, 2.3, 58.0, 33.0, 7.7, [['1 handful', 30]], ['banana chips', 'upperi', 'chips'], E),
  f('biscuit', 'Biscuits (glucose/marie)', 'Snacks & sweets', 450, 7.0, 75.0, 14.0, 2.0, [['1 biscuit', 8]], ['biscuit', 'biscuits', 'marie'], E),
  f('dark-chocolate', 'Dark chocolate (70%)', 'Snacks & sweets', 598, 7.8, 45.9, 42.6, 10.9, [['2 squares', 20]], ['dark chocolate', 'chocolate']),
];

export const FOOD_CATS = Array.from(new Set(FOODS.map((x) => x.cat)));

export function macrosFor(food: Food, grams: number) {
  const k = grams / 100;
  return {
    kcal: food.kcal * k, p: food.p * k, c: food.c * k, f: food.f * k, fib: food.fib * k,
  };
}
