import React from 'react';
import {Pressable, ScrollView, Text, View} from 'react-native';
import {personalBests} from './records';

/**
 * Show personal records only where a saved weight has a recognisable unit.
 */
export default function Records({catches, toUK, styles, onBack, onOpenCatch}) {
  const bests=personalBests(catches);
  return <ScrollView contentContainerStyle={styles.content}><Pressable accessibilityRole="button" onPress={onBack}><Text style={styles.textLink}>‹ Back to your trips</Text></Pressable><Text style={styles.eyebrow}>YOUR FISHING</Text><Text style={styles.title}>Personal records</Text><Text style={styles.subtitle}>Your heaviest recorded catch for each saved species name.</Text>
    {bests.length===0&&<View style={styles.empty}><Text style={styles.cardTitle}>No comparable weights yet</Text><Text style={styles.muted}>Add a weight with a unit, such as 3 lb 4 oz or 1.5 kg.</Text></View>}
    {bests.map(({catchItem})=><Pressable key={catchItem.id} accessibilityRole="button" onPress={()=>onOpenCatch(catchItem)} style={styles.fishRow}><View style={styles.rowText}><Text style={styles.cardTitle}>{catchItem.species}</Text><Text style={styles.small}>{toUK(catchItem.date)||'Date not recorded'} · {catchItem.place||'Location not recorded'}</Text></View><Text style={styles.cardTitle}>{catchItem.weight}</Text><Text style={styles.chevron}> ›</Text></Pressable>)}
    <Text style={styles.small}>Only weights with recognisable units are compared. Entries without units or in other formats are omitted, and species are grouped by their saved names.</Text>
  </ScrollView>;
}
