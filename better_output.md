# Better Outputs
## Objective
Looking for a way to have better and more informative output. Also the code does
output in many places, so a single entry point for this would be great.

## Design
- think of a data structure that I can use to determine output
- I need to persist previous pomodoro records, so support that too
- Strike through and color support for things I've done and things in progress
  and things I've chose not to do


Workflow:
- on start, type out tasks I want to do
- list the tasks with a number on them e.g. 1 play game, 2 eat lunch, ...
- once done, I can mark them as done using d and the number of the item
- a tasks marked as done is crossed out in the screen
- similarly, I can mark a task as cancelled using c and the number of the item.
- a cancelled item will be greyed out on the list of items
- items can be added to the list using the a keyword.

Example:

```
Pomodoro 1
Add items: play game, eat lunch, read book

# above gets cleared and this is displayed
Pomodoro 1
Plan: 1 play game, 2 eat lunch, 3 read book

# After done with task 1 press d and get
Pomodoro 1
Plan: 1 play game, 2 eat lunch, 3 read book
Enter index to mark as done: 1

# This is displayed
Pomodoro 1
Plan: ~1 play game~, 2 eat lunch, 3 read book

# Similar workflow as c
# a has a similar workflow as the initial prompt but adds to the list
```
